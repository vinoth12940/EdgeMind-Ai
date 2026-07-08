// LocalAIEdgeApp/Services/Tools/WebSearchTool.swift
import Foundation

/// `web_search` — the original agentic tool, now wrapped behind the `Tool` protocol.
/// It preserves the EXACT behavior the published v0.1.0 search feature relies on:
/// `SearchQueryRefiner` rewrites the query, `SearchGatewayFactory` resolves the
/// provider, and the returned `ToolResult.searchContext` flows through the existing
/// structured render path (`PromptRenderer` / `MLXInferenceService.buildSystemPrompt`).
struct WebSearchTool: Tool {
    let name = "web_search"

    let definition = ToolDefinition(
        name: "web_search",
        summary: "Search the web for current or real-time information (news, scores, weather, prices, recent events). Only use this when you need information you do not already have.",
        parameters: ["query": "the search query"]
    )

    func run(argsJSON: String, context: ToolContext) async -> ToolResult {
        guard let query = WebSearchTool.extractQuery(argsJSON), !query.isEmpty else {
            return .error(toolName: name,
                          message: "Missing \"query\" argument. Send {\"name\": \"web_search\", \"arguments\": {\"query\": \"...\"}}.")
        }

        guard let gateway = SearchGatewayFactory.make(settings: context.settings) else {
            return .error(toolName: name,
                          message: "No web search provider is configured. Ask the user to set one up in Settings, or answer from your own knowledge.")
        }

        let refinedQuery = SearchQueryRefiner.refine(query, conversation: context.conversation)
        do {
            let searchContext = try await gateway.search(query: refinedQuery)
            return ToolResult(toolName: name,
                              output: "Web search completed for \"\(query)\". Results are provided in the context below.",
                              citations: searchContext.citations,
                              searchContext: searchContext)
        } catch {
            return .error(toolName: name,
                          message: "Search failed: \(error.localizedDescription). Answer from your own knowledge if you can.")
        }
    }

    /// Extracts the query from any of the shapes models emit:
    /// `{"name":"web_search","arguments":{"query":"..."}}`, `{"query":"..."}`, etc.
    static func extractQuery(_ argsJSON: String) -> String? {
        let trimmed = argsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Bare string fallback.
            return trimmed.isEmpty ? nil : trimmed
        }

        // Nested arguments dict: {"name": "...", "arguments": {"query": "..."}}
        if let args = json["arguments"] as? [String: Any] {
            if let q = args["query"] as? String, !q.isEmpty { return q }
        }
        // String-encoded arguments: {"arguments": "{\"query\":\"...\"}"}
        if let argsStr = json["arguments"] as? String,
           let argsData = argsStr.data(using: .utf8),
           let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
           let q = argsDict["query"] as? String, !q.isEmpty {
            return q
        }
        // Flat query key.
        if let q = json["query"] as? String, !q.isEmpty { return q }
        return nil
    }
}
