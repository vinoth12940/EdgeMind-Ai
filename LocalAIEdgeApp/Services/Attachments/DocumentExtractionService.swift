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

    static func attachment(from url: URL) throws -> ChatAttachment {
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
            return ChatAttachment(
                kind: .pdf,
                fileName: fileName,
                mimeType: "application/pdf",
                rawData: nil,
                extractedText: truncate(pageText)
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

    static func promptContext(from attachments: [ChatAttachment]) -> String {
        let documentBlocks = attachments.compactMap { attachment -> String? in
            guard let text = attachment.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return "### \(attachment.fileName)\n\(text)"
        }

        guard !documentBlocks.isEmpty else { return "" }
        return """

Attached document context:
\(documentBlocks.joined(separator: "\n\n"))
"""
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
