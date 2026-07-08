// LocalAIEdgeApp/Services/Tools/Tool.swift
import Foundation

/// A single callable tool that the model can invoke during a chat turn.
/// Tools are pure functions over their arguments plus a `ToolContext`;
/// they read only what is handed to them and run off the main actor.
protocol Tool {
    /// Stable identifier the model emits inside `<tool_call>` JSON, e.g. `"web_search"`.
    var name: String { get }

    /// Human/protocol-facing description used to build the injected `# Tools` prompt section.
    var definition: ToolDefinition { get }

    /// Execute the tool. Returns a `ToolResult` whose `output` text is injected into the
    /// system prompt for the next inference pass. Must never throw for control-flow —
    /// surface failures as a `ToolResult` with an error message so the model can recover.
    func run(argsJSON: String, context: ToolContext) async -> ToolResult
}

/// Static description of a tool, used to render the prompt section the model reads.
struct ToolDefinition {
    let name: String
    let summary: String
    /// Parameter names with one-line descriptions, e.g. `["query": "the search query"]`.
    let parameters: [String: String]

    /// Renders the parameter line for the prompt, e.g.
    /// `Parameters: query (string) — the search query`
    var parametersPromptLine: String {
        guard !parameters.isEmpty else { return "Parameters: none" }
        let parts = parameters.map { "\($0.key) (string) — \($0.value)" }
        return "Parameters: " + parts.joined(separator: "; ")
    }
}

/// Result of executing a tool. `output` is always plain text injected into the next
/// inference pass. `searchContext`/`citations` are only populated by `web_search` so it
/// can keep using the structured rendering path the published search feature relies on.
struct ToolResult {
    let toolName: String
    let output: String
    let citations: [SearchCitation]
    let searchContext: SearchContext?

    init(toolName: String,
         output: String,
         citations: [SearchCitation] = [],
         searchContext: SearchContext? = nil) {
        self.toolName = toolName
        self.output = output
        self.citations = citations
        self.searchContext = searchContext
    }

    /// Convenience for tools that produced an error (bad args, unavailable, etc.).
    /// The model sees the reason and can retry or answer without the tool.
    static func error(toolName: String, message: String) -> ToolResult {
        ToolResult(toolName: toolName, output: "Error: \(message)")
    }
}

/// Per-turn dependencies handed to every tool. Built fresh in `ChatView` before
/// dispatch. All fields are value types.
struct ToolContext {
    let settings: AppSettings
    let conversation: [ChatMessage]
    let chatSessions: [ChatSession]
    let attachedDocuments: [ChatAttachment]
    let installedModel: InstalledModel?

    /// Convenience: only attachments that carry extractable document text.
    var readableDocuments: [ChatAttachment] {
        attachedDocuments.filter { $0.kind != .image }
    }
}
