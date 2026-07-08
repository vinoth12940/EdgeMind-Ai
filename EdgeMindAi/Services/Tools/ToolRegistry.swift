// LocalAIEdgeApp/Services/Tools/ToolRegistry.swift
import Foundation

/// Central registry of every tool the app ships. `ChatView` asks the registry which
/// tools are available for the current turn (gated by config + context), asks it to
/// render the injected `# Tools` prompt section, and routes `<tool_call>` dispatch
/// through `dispatch(name:argsJSON:context:)`.
enum ToolRegistry {

    /// Hard cap on consecutive tool calls within a single user turn. Bounds latency and
    /// prevents pathological loops. The model is told "call at most once per response",
    /// but the loop in `ChatView` allows N passes total because each tool result may
    /// legitimately prompt a follow-up tool call.
    static let maxIterations = 3

    /// Every tool the app knows about, in canonical order. Order is stable so the
    /// rendered prompt section is deterministic across launches.
    static let allTools: [Tool] = [
        WebSearchTool(),
        CalculateTool(),
        SearchHistoryTool(),
        ReadDocumentTool(),
        GetCurrentTimeTool(),
        GetDeviceInfoTool(),
        GetBatteryLevelTool()
    ]

    /// Returns the subset of tools available for this turn. Tools that have no useful
    /// answer (or no permission/support) are omitted so the model can't call them.
    static func availableTools(context: ToolContext) -> [Tool] {
        var available: [Tool] = []

        // web_search only if a provider is configured.
        if SearchGatewayFactory.make(settings: context.settings) != nil {
            available.append(WebSearchTool())
        }

        // calculate, time, device, battery — always available.
        available.append(CalculateTool())
        available.append(GetCurrentTimeTool())
        available.append(GetDeviceInfoTool())
        available.append(GetBatteryLevelTool())

        // search_chats — only if there are past sessions to search.
        if !context.chatSessions.isEmpty {
            available.append(SearchHistoryTool())
        }

        // read_document — only if a readable document is attached.
        if !context.readableDocuments.isEmpty {
            available.append(ReadDocumentTool())
        }

        return available
    }

    /// Builds the `# Tools` prompt section injected into the system prompt. Generalizes
    /// the old hardcoded `toolCallDefinition` (which described only `web_search`).
    static func renderPromptSection(for tools: [Tool]) -> String {
        guard !tools.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("")
        lines.append("# Tools")
        lines.append("")
        lines.append("You have access to the following tools. Call one when it would help answer the user's request. Each tool returns its result, which you will see in your context on the next turn.")
        lines.append("")

        for tool in tools {
            lines.append("## \(tool.definition.name)")
            lines.append(tool.definition.summary)
            lines.append(tool.definition.parametersPromptLine)
            lines.append("")
        }

        lines.append("To call a tool, output ONLY this block (no other text before the closing tag):")
        lines.append("<tool_call>")
        lines.append("{\"name\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}")
        lines.append("</tool_call>")
        lines.append("")
        lines.append("Rules:")
        lines.append("- Call a tool only when it gives you information you genuinely need and do not already have.")
        lines.append("- Output ONLY the tool-call block when you call a tool. Do not add narration around it.")
        lines.append("- Call at most ONE tool per response. After a tool result arrives, answer the user or call another tool.")
        lines.append("- If a tool returns an error, explain it briefly and answer from your own knowledge if you can.")

        return lines.joined(separator: "\n")
    }

    /// Looks up a tool by the name the model emitted and runs it. Returns nil for
    /// unknown tool names (the caller treats that as plain text / model mistake).
    static func dispatch(name: String, argsJSON: String, context: ToolContext) async -> ToolResult? {
        guard let tool = allTools.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            return nil
        }
        return await tool.run(argsJSON: argsJSON, context: context)
    }
}
