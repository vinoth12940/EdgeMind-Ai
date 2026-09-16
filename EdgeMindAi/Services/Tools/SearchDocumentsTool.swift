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

    /// Extracts the query from any shape models emit, mirroring
    /// `WebSearchTool.extractQuery`: a flat `{"query": "…"}`, a nested
    /// `{"arguments": {"query": "…"}}`, a JSON-encoded `arguments` string, or a
    /// BARE STRING — which is what Apple Intelligence sends
    /// (`{"name": "search_documents", "arguments": "vacation policy"}`).
    ///
    /// The bare-string case was missing here even though every sibling tool
    /// handles it, so Apple Intelligence document search always failed with
    /// "A non-empty 'query' argument is required." and the model fell back to
    /// telling the user to upload the document.
    static func extractQuery(_ argsJSON: String) -> String? {
        let trimmed = argsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let query = json["query"] as? String, !query.isEmpty {
                return query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let query = json["q"] as? String, !query.isEmpty {
                return query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let args = json["arguments"] as? [String: Any],
               let query = args["query"] as? String, !query.isEmpty {
                return query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // String-encoded arguments: {"arguments": "{\"query\":\"…\"}"} or a
            // bare value: {"arguments": "vacation policy"}.
            if let argsStr = json["arguments"] as? String, !argsStr.isEmpty {
                if let argsData = argsStr.data(using: .utf8),
                   let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
                   let query = argsDict["query"] as? String, !query.isEmpty {
                    return query.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return argsStr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        // Bare string fallback: the model sent the raw query, not JSON.
        return trimmed
    }
}
