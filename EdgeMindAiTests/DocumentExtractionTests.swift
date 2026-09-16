import XCTest
import UIKit
@testable import EdgeMindAi

/// Covers the two ways an attached document used to contribute nothing:
/// image-only PDFs (no text layer) and long documents whose useful content sat
/// past the point where small-context runtimes stopped reading.
final class DocumentExtractionTests: XCTestCase {

    // MARK: - Relevance-based excerpting

    private func longDocument(answerAtEnd: Bool) -> String {
        let filler = String(repeating: "general background paragraph about unrelated topics. ", count: 200)
        let answer = "Your policy number is SF-99887766 and the deductible is 500 dollars."
        return answerAtEnd ? filler + "\n\n" + answer : answer + "\n\n" + filler
    }

    func test_excerpt_findsAnswerBuriedAtTheEnd() {
        let text = longDocument(answerAtEnd: true)
        let budget = 600

        let excerpt = DocumentExcerptBuilder.excerpt(
            from: text,
            maxCharacters: budget,
            query: "what is my policy number and deductible"
        )

        XCTAssertLessThanOrEqual(excerpt.count, budget)
        XCTAssertTrue(excerpt.contains("SF-99887766"), "the relevant passage must survive excerpting")
    }

    func test_excerpt_respectsBudget() {
        let excerpt = DocumentExcerptBuilder.excerpt(
            from: longDocument(answerAtEnd: false),
            maxCharacters: 300,
            query: "deductible"
        )

        XCTAssertLessThanOrEqual(excerpt.count, 300)
    }

    func test_excerpt_leavesShortTextAlone() {
        let text = "Short card text."

        let excerpt = DocumentExcerptBuilder.excerpt(from: text, maxCharacters: 500, query: "anything")

        XCTAssertEqual(excerpt, text)
    }

    func test_excerpt_withoutQuery_fallsBackToTrim() {
        let text = String(repeating: "x", count: 5_000)

        let excerpt = DocumentExcerptBuilder.excerpt(from: text, maxCharacters: 400, query: "")

        XCTAssertLessThanOrEqual(excerpt.count, 400)
        XCTAssertFalse(excerpt.isEmpty)
    }

    func test_promptContext_usesQueryToPickTheRelevantPart() {
        let attachment = ChatAttachment(
            kind: .pdf,
            fileName: "State Farm Insurance Card.pdf",
            mimeType: "application/pdf",
            extractedText: longDocument(answerAtEnd: true)
        )

        let context = DocumentExtractionService.promptContext(
            from: [attachment],
            maxCharacters: 700,
            query: "what is my policy number"
        )

        XCTAssertTrue(context.contains("State Farm Insurance Card.pdf"))
        XCTAssertTrue(context.contains("SF-99887766"))
        XCTAssertLessThanOrEqual(context.count, 700)
    }

    // MARK: - Tiny text layers / unreadable documents

    func test_hasNoReadableText_detectsEmptyDocuments() {
        let empty = ChatAttachment(kind: .pdf, fileName: "scan.pdf", mimeType: "application/pdf", extractedText: "")
        let whitespace = ChatAttachment(kind: .pdf, fileName: "scan2.pdf", mimeType: "application/pdf", extractedText: "   \n ")
        let readable = ChatAttachment(kind: .pdf, fileName: "ok.pdf", mimeType: "application/pdf", extractedText: "Policy SF-1")
        let image = ChatAttachment(kind: .image, fileName: "photo.jpg", mimeType: "image/jpeg", rawData: Data([1]))

        XCTAssertTrue(DocumentExtractionService.hasNoReadableText(empty))
        XCTAssertTrue(DocumentExtractionService.hasNoReadableText(whitespace))
        XCTAssertFalse(DocumentExtractionService.hasNoReadableText(readable))
        // Images go to vision models, not the text path.
        XCTAssertFalse(DocumentExtractionService.hasNoReadableText(image))
    }

    func test_promptContext_skipsEmptyDocuments() {
        let empty = ChatAttachment(kind: .pdf, fileName: "scan.pdf", mimeType: "application/pdf", extractedText: "")

        let context = DocumentExtractionService.promptContext(from: [empty], maxCharacters: 1_000, query: "policy")

        XCTAssertEqual(context, "")
    }

    // MARK: - OCR fallback

    /// Renders text into an image (as a scanned page would be) and checks the
    /// Vision fallback reads it back.
    func test_ocr_readsTextFromARenderedImage() async {
        let image = Self.imageWithText("INSURANCE POLICY SF-99887766")

        let recognized = await DocumentTextRecognizer.text(in: image)

        XCTAssertFalse(recognized.isEmpty, "Vision OCR returned nothing in this environment")
        XCTAssertTrue(
            recognized.uppercased().contains("SF") || recognized.uppercased().contains("INSURANCE"),
            "unexpected OCR output: \(recognized)"
        )
    }

    func test_ocr_onBlankImage_returnsNothing() async {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 120), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        }

        let recognized = await DocumentTextRecognizer.text(in: blank)

        XCTAssertTrue(recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func imageWithText(_ text: String) -> UIImage {
        let size = CGSize(width: 900, height: 220)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            text.draw(at: CGPoint(x: 30, y: 80), withAttributes: attributes)
        }
    }
}
