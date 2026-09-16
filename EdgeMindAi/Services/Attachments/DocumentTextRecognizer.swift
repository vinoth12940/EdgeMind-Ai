import Foundation
import UIKit
import Vision
import PDFKit
import OSLog

private let recognizerLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "DocumentTextRecognizer")

/// On-device OCR for documents that carry no text layer (scans, photos of cards,
/// image-only PDFs). Uses Apple's Vision framework locally — nothing is uploaded.
///
/// `PDFDocument.page(at:).string` returns nothing for a scanned page, which used
/// to leave the attachment silently empty so the model received no document at
/// all. This runs only as a fallback when the text layer is missing.
enum DocumentTextRecognizer {
    /// Below this many characters the text layer is treated as absent and OCR runs.
    static let minimumTextLayerCharacters = 16

    /// Renders a PDF page and recognizes its text.
    static func text(in page: PDFPage) async -> String {
        guard let image = render(page: page), let cgImage = image.cgImage else { return "" }
        return await text(in: cgImage)
    }

    /// Recognizes text in an image.
    static func text(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await text(in: cgImage)
    }

    static func text(in cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let recognized = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    continuation.resume(returning: recognized)
                } catch {
                    recognizerLogger.error("OCR failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: "")
                }
            }
        }
    }

    /// Renders a PDF page at a resolution that is good for OCR without blowing
    /// up memory on very large pages.
    private static func render(page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let longestSide = max(bounds.width, bounds.height)
        let scale = min(3.0, 2_200.0 / longestSide)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // PDF coordinates are bottom-left origin; flip into UIKit space.
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
}
