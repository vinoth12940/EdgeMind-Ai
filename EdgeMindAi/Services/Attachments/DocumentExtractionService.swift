import Foundation
import PDFKit
import UniformTypeIdentifiers

enum DocumentExtractionError: LocalizedError {
    case unsupportedType
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "This file type is not supported yet. Attach TXT, Markdown, CSV, PDF, or an image."
        case .unreadableFile:
            return "The selected file could not be read."
        }
    }
}

enum DocumentExtractionService {
    static let supportedTypes: [UTType] = [
        .plainText,
        .text,
        .commaSeparatedText,
        .pdf,
        UTType(filenameExtension: "md") ?? .text,
        UTType(filenameExtension: "markdown") ?? .text
    ]
    private static let maxExtractedCharacters = 20_000

    static func attachment(from url: URL) async throws -> ChatAttachment {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .nameKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        let fileName = values?.name ?? url.lastPathComponent

        if type?.conforms(to: .pdf) == true {
            guard let document = PDFDocument(url: url) else { throw DocumentExtractionError.unreadableFile }
            let pageText = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n\n")
            let resolved = await resolveTextLayer(pageText) {
                var recognized: [String] = []
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    let text = await DocumentTextRecognizer.text(in: page)
                    if !text.isEmpty { recognized.append(text) }
                }
                return recognized.joined(separator: "\n\n")
            }
            return ChatAttachment(
                kind: .pdf,
                fileName: fileName,
                mimeType: "application/pdf",
                rawData: nil,
                extractedText: truncate(resolved)
            )
        }

        if type?.conforms(to: .commaSeparatedText) == true || url.pathExtension.lowercased() == "csv" {
            let text = try readText(url)
            return ChatAttachment(kind: .csv, fileName: fileName, mimeType: "text/csv", rawData: nil, extractedText: truncate(text))
        }

        if type?.conforms(to: .text) == true || ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()) {
            let text = try readText(url)
            let isMarkdown = ["md", "markdown"].contains(url.pathExtension.lowercased())
            return ChatAttachment(
                kind: isMarkdown ? .markdown : .text,
                fileName: fileName,
                mimeType: isMarkdown ? "text/markdown" : "text/plain",
                rawData: nil,
                extractedText: truncate(text)
            )
        }

        throw DocumentExtractionError.unsupportedType
    }

    /// Library imports cap extracted text at 2 MB per document (spec §3); the
    /// 20,000-character cap above still applies to prompt-inlined chat attachments.
    static let libraryMaxCharacters = 2_000_000

    /// Page-addressable extraction for the document library. PDFs keep one entry
    /// per page so chunks can carry their page number; everything else is a
    /// single "page".
    static func libraryPages(from url: URL) async throws -> (fileName: String, kind: ChatAttachment.Kind, pages: [String]) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .nameKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        let fileName = values?.name ?? url.lastPathComponent
        var remaining = libraryMaxCharacters

        func capped(_ text: String) -> String {
            guard remaining > 0 else { return "" }
            let slice = String(text.prefix(remaining))
            remaining -= slice.count
            return slice
        }

        if type?.conforms(to: .pdf) == true {
            guard let document = PDFDocument(url: url) else { throw DocumentExtractionError.unreadableFile }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let textLayer = page.string ?? ""
                let resolved = await resolveTextLayer(textLayer) {
                    await DocumentTextRecognizer.text(in: page)
                }
                pages.append(capped(resolved))
            }
            return (fileName, .pdf, pages)
        }

        if type?.conforms(to: .commaSeparatedText) == true || url.pathExtension.lowercased() == "csv" {
            return (fileName, .csv, [capped(try readText(url))])
        }

        if type?.conforms(to: .text) == true || ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()) {
            let isMarkdown = ["md", "markdown"].contains(url.pathExtension.lowercased())
            return (fileName, isMarkdown ? .markdown : .text, [capped(try readText(url))])
        }

        throw DocumentExtractionError.unsupportedType
    }

    /// Inlines attached documents for the prompt, bounded to `maxCharacters` in
    /// total. The bound is required: a 20,000-character PDF is roughly 5,000
    /// tokens, which overflows small-context runtimes (LiteRT-LM caps at 2048 and
    /// rejects the request outright). Callers pass
    /// `InferenceBudget.documentContextBudget(for:)`; the default preserves the
    /// historical 20,000-character cap.
    static func promptContext(
        from attachments: [ChatAttachment],
        maxCharacters: Int = maxExtractedCharacters,
        query: String = ""
    ) -> String {
        let header = "\n\nAttached document context:\n"
        // Leave room for the header and the per-document label.
        var remaining = max(0, maxCharacters - header.count)

        var documentBlocks: [String] = []
        for attachment in attachments {
            guard remaining > 0 else { break }
            guard let text = attachment.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                continue
            }

            let label = "### \(attachment.fileName)\n"
            guard label.count < remaining else { continue }
            remaining -= label.count

            let body = DocumentExcerptBuilder.excerpt(from: text, maxCharacters: remaining, query: query)
            remaining -= body.count
            documentBlocks.append(label + body)
        }

        guard !documentBlocks.isEmpty else { return "" }
        return header + documentBlocks.joined(separator: "\n\n")
    }

    /// Uses the embedded text layer when it has real content and falls back to
    /// on-device OCR otherwise (scans and photos of documents have no text layer).
    private static func resolveTextLayer(_ textLayer: String, ocr: () async -> String) async -> String {
        let trimmed = textLayer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count < DocumentTextRecognizer.minimumTextLayerCharacters else { return textLayer }

        let recognized = (await ocr()).trimmingCharacters(in: .whitespacesAndNewlines)
        return recognized.isEmpty ? textLayer : recognized
    }

    /// True when an attachment carries no usable text even after OCR.
    static func hasNoReadableText(_ attachment: ChatAttachment) -> Bool {
        guard attachment.kind != .image else { return false }
        let text = attachment.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty
    }

    private static func readText(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
            return text
        }
        throw DocumentExtractionError.unreadableFile
    }

    private static func truncate(_ text: String) -> String {
        guard text.count > maxExtractedCharacters else { return text }
        return String(text.prefix(maxExtractedCharacters))
    }
}
