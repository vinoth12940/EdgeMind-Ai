// LocalAIEdgeApp/Services/Tools/ReadDocumentTool.swift
import Foundation

/// `read_document` — let the model pull the text of an attached document on demand
/// instead of having it pre-injected into the prompt. Reuses the extraction already
/// performed by `DocumentExtractionService` and stored on `ChatAttachment.extractedText`.
///
/// If the model names a specific file, that one is returned; otherwise the readable
/// documents are returned in order. Output is bounded to keep the prompt small.
struct ReadDocumentTool: Tool {
    let name = "read_document"

    let definition = ToolDefinition(
        name: "read_document",
        summary: "Read the extracted text of a document the user has attached to this conversation (PDF, TXT, Markdown, CSV). Use the file name to pick one, or omit it to read all attached documents.",
        parameters: ["file_name": "optional name of the attached document to read"]
    )

    /// Hard cap on returned characters per document so a huge PDF can't blow the budget.
    static let maxCharactersPerDocument = 8_000
    /// Cap on total characters across all returned documents.
    static let maxTotalCharacters = 12_000

    func run(argsJSON: String, context: ToolContext) async -> ToolResult {
        let docs = context.readableDocuments
        if docs.isEmpty {
            return .error(toolName: name,
                          message: "No readable documents are attached to this conversation.")
        }

        let requested = ReadDocumentTool.extractFileName(argsJSON)
        var selected: [ChatAttachment]
        if let needle = requested?.lowercased(), !needle.isEmpty {
            selected = docs.filter { $0.fileName.lowercased().contains(needle) }
            if selected.isEmpty {
                let names = docs.map { $0.fileName }.joined(separator: ", ")
                return .error(toolName: name,
                              message: "No attached document matches \"\(requested ?? "")\". Available: \(names).")
            }
        } else {
            selected = docs
        }

        var sections: [String] = []
        var total = 0
        for doc in selected {
            let body = doc.extractedText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\r", with: "")
            ?? "(no extractable text)"
            let capped = Self.cap(body, remaining: Self.maxTotalCharacters - total)
            sections.append("## \(doc.fileName)\n\(capped)")
            total += capped.count
            if total >= Self.maxTotalCharacters { break }
        }

        return ToolResult(toolName: name, output: sections.joined(separator: "\n\n"))
    }

    private static func cap(_ text: String, remaining: Int) -> String {
        let limit = min(Self.maxCharactersPerDocument, max(0, remaining))
        if text.count <= limit { return text }
        let end = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[text.startIndex..<end]) + "\n…[truncated]"
    }

    static func extractFileName(_ argsJSON: String) -> String? {
        let trimmed = argsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return trimmed.isEmpty ? nil : trimmed
        }
        if let s = json["file_name"] as? String { return s }
        if let s = json["file"] as? String { return s }
        if let s = json["name"] as? String { return s }
        return nil
    }
}
