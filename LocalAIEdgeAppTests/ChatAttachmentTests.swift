import XCTest
@testable import LocalAIEdgeApp

final class ChatAttachmentTests: XCTestCase {
    func test_largeRawAttachmentIsDroppedButExtractedTextIsKept() {
        let attachment = ChatAttachment(
            kind: .pdf,
            fileName: "notes.pdf",
            mimeType: "application/pdf",
            rawData: Data(repeating: 1, count: 16),
            extractedText: "Project Cedar"
        )

        let sanitized = attachment.sanitized(maxRawBytes: 8, maxExtractedCharacters: 200)

        XCTAssertNil(sanitized.rawData)
        XCTAssertEqual(sanitized.extractedText, "Project Cedar")
    }

    func test_extractedTextIsTruncatedForPersistence() {
        let attachment = ChatAttachment(
            kind: .text,
            fileName: "long.txt",
            mimeType: "text/plain",
            extractedText: String(repeating: "a", count: 20)
        )

        let sanitized = attachment.sanitized(maxRawBytes: 8, maxExtractedCharacters: 5)

        XCTAssertEqual(sanitized.extractedText, "aaaaa")
    }

    func test_promptContextIncludesDocumentAttachmentText() {
        let attachment = ChatAttachment(
            kind: .markdown,
            fileName: "brief.md",
            mimeType: "text/markdown",
            extractedText: "The launch code is Cedar."
        )

        let context = DocumentExtractionService.promptContext(from: [attachment])

        XCTAssertTrue(context.contains("Attached document context"))
        XCTAssertTrue(context.contains("brief.md"))
        XCTAssertTrue(context.contains("Cedar"))
    }

    func test_imageInputPolicyAllowsVerifiedVisionModelsOnly() throws {
        let store = RuntimeProfileStore()
        let visionItem = MockCatalogData.items.first {
            $0.supportsVision && ModelRuntimeResolver.resolve(catalog: $0, store: store).vision == .imageAndText
        }
        let textOnlyItem = MockCatalogData.items.first {
            !$0.supportsVision && $0.primaryUse == .chat
        }

        let visionModel = InstalledModel(catalogItem: try XCTUnwrap(visionItem), installState: .installed)
        let textOnlyModel = InstalledModel(catalogItem: try XCTUnwrap(textOnlyItem), installState: .installed)

        XCTAssertTrue(ChatInputCapability.acceptsImage(visionModel, profileStore: store))
        XCTAssertFalse(ChatInputCapability.acceptsImage(textOnlyModel, profileStore: store))
        XCTAssertTrue(ChatInputCapability.imageUnsupportedMessage.contains("vision model"))
    }
}
