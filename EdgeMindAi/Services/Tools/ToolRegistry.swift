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
        SearchDocumentsTool(),
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

        // search_documents — only when the library has indexed documents and the
        // user has the feature enabled.
        if context.settings.documentSearchEnabled,
           let index = context.documentSearchIndex,
           !index.isEmpty {
            available.append(SearchDocumentsTool())
        }

        return available
    }

    /// Builds the `# Tools` prompt section injected into the system prompt. Generalizes
    /// the old hardcoded `toolCallDefinition` (which described only `web_search`).
    ///
    /// `format` must be the model's own verified tool-call convention. The section
    /// used to hardcode the XML/JSON form for every model, so Gemma 4 (which emits
    /// `call:NAME{…}`) and LFM2.5 (which emits `<|tool_call_start|>`) were instructed
    /// to produce syntax that is not their native convention — and then the parser
    /// was expected to cope. It does cope, but the model is far more reliable when
    /// asked for the shape it was trained on.
    static func renderPromptSection(for tools: [Tool], format: ToolCallFormat = .xmlToolCall) -> String {
        guard !tools.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("")
        lines.append("# Tools")
        lines.append("")
        lines.append("You have access to the following tools. Call one ONLY when the user's request genuinely needs information you do not already have. Each tool returns its result, which you will see in your context on the next turn.")
        lines.append("")

        for tool in tools {
            lines.append("## \(tool.definition.name)")
            lines.append(tool.definition.summary)
            lines.append(tool.definition.parametersPromptLine)
            lines.append("")
        }

        lines.append("To call a tool, output ONLY this block (no other text before the closing tag):")
        lines.append(contentsOf: exampleLines(for: format))
        lines.append("")
        lines.append("Rules:")
        lines.append("- Do NOT call a tool for greetings, thanks, small talk, or anything you can already answer. Just reply normally.")
        lines.append("- Call a tool only when it gives you information you genuinely need and do not already have.")
        lines.append("- Being offered a tool is not a reason to use it.")
        lines.append("- Output ONLY the tool-call block when you call a tool. Do not add narration around it.")
        lines.append("- Call at most ONE tool per response. After a tool result arrives, answer the user or call another tool.")
        lines.append("- If a tool returns an error, explain it briefly and answer from your own knowledge if you can.")

        return lines.joined(separator: "\n")
    }

    /// One concrete example call, rendered in the model's own convention. These match
    /// exactly what `StreamProcessor` / `GemmaToolCallPayload` parse.
    private static func exampleLines(for format: ToolCallFormat) -> [String] {
        switch format {
        case .xmlToolCall:
            return [
                "<tool_call>",
                "{\"name\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}",
                "</tool_call>"
            ]
        case .gemmaNativeToolCall:
            return [
                "<|tool_call>",
                "call:tool_name{param:<|\"|>value<|\"|>}",
                "<tool_call|>"
            ]
        case .liquidToolCall:
            return [
                "<|tool_call_start|>",
                "{\"name\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}",
                "<|tool_call_end|>"
            ]
        }
    }

    /// Looks up a tool by the name the model emitted and runs it. Returns nil for
    /// unknown tool names (the caller treats that as plain text / model mistake).
    static func dispatch(name: String, argsJSON: String, context: ToolContext) async -> ToolResult? {
        guard let tool = allTools.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            return nil
        }

        // Only run tools that were actually offered for this turn. `availableTools`
        // exists so the model "can't call" a gated tool, but dispatch previously ran
        // anything in `allTools` — so a model could invoke `search_documents` with the
        // feature switched off, or `search_chats` with no history, and burn one of the
        // three loop iterations on a guaranteed failure.
        let offered = availableTools(context: context)
            .contains { $0.name.lowercased() == tool.name.lowercased() }
        guard offered else {
            return .error(
                toolName: tool.name,
                message: "The \(tool.name) tool is not available in this conversation."
            )
        }

        return await tool.run(argsJSON: argsJSON, context: context)
    }
}
