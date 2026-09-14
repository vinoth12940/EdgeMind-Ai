import Foundation

/// Searches the on-device document library. Returns labeled passages
/// (`[fileName p.12] …`) plus citation-style sources for the answer footer.
/// Runs entirely locally.
struct SearchDocumentsTool: Tool {
    var name: String { "search_documents" }

    var definition: ToolDefinition {
        ToolDefinition(
            name: "search_documents",
            summary: "Search the user's on-device document library (imported PDFs, text, Markdown, CSV) and return the most relevant passages. Use this when the user asks about their documents, files, or notes.",
            parameters: ["query": "what to look for in the document library"]
        )
    }

    func run(argsJSON: String, context: ToolContext) async -> ToolResult {
        guard context.settings.documentSearchEnabled else {
            return .error(toolName: name, message: "Document search is turned off in Settings.")
        }
        guard let index = context.documentSearchIndex, !index.isEmpty else {
            return .error(toolName: name, message: "No indexed documents are available.")
        }
        guard let query = Self.extractQuery(argsJSON), !query.isEmpty else {
            return .error(toolName: name, message: "A non-empty 'query' argument is required.")
        }

        let hits = DocumentSearchService.search(query: query, index: index)
        guard !hits.isEmpty else {
            return ToolResult(
                toolName: name,
                output: "No passages in the document library matched \"\(query)\"."
            )
        }

        let budget = context.installedModel.map { InferenceBudget.documentContextBudget(for: $0) } ?? 4_000
        let rendered = DocumentSearchService.renderHits(hits, budgetCharacters: budget)
        return ToolResult(
            toolName: name,
            output: rendered,
            citations: hits.map(Self.citation(from:))
        )
    }

    /// A `file`-style source so each passage shows up in the answer's Sources list.
    static func citation(from hit: DocumentHit) -> SearchCitation {
        var components = URLComponents()
        components.scheme = "edgemindai"
        components.host = "document"
        components.path = "/\(hit.documentID.uuidString)"
        if let page = hit.pageNumber {
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }
        let url = components.url ?? URL(string: "edgemindai://document/\(hit.documentID.uuidString)")!
        let title = hit.pageNumber.map { "\(hit.fileName) — p.\($0)" } ?? hit.fileName
        return SearchCitation(
            title: title,
            url: url,
            snippet: String(hit.text.prefix(160))
        )
    }

    static func extractQuery(_ argsJSON: String) -> String? {
        guard let data = argsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let query = json["query"] as? String { return query.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let args = json["arguments"] as? [String: Any], let query = args["query"] as? String {
            return query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
