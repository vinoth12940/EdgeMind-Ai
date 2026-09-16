import Foundation

extension ChatTurnEngine {
    /// Extract a web_search tool call from raw text (handles both standard and Gemma 4 formats).
    /// Used as a fallback when StreamProcessor misses <tool_call> due to tag splitting across tokens.
    static func extractToolCallQuery(from text: String) -> String? {
        // Try standard <tool_call>...</tool_call>
        if let openRange = text.range(of: "<tool_call>", options: .caseInsensitive),
           let closeRange = text.range(of: "</tool_call>", options: .caseInsensitive, range: openRange.upperBound..<text.endIndex) {
            return parseWebSearchQuery(String(text[openRange.upperBound..<closeRange.lowerBound]))
        }
        // Try Gemma 4 native <|tool_call>...<tool_call|>
        if let openRange = text.range(of: "<|tool_call>", options: .caseInsensitive),
           let closeRange = text.range(of: "<tool_call|>", options: .caseInsensitive, range: openRange.upperBound..<text.endIndex) {
            return parseWebSearchQuery(String(text[openRange.upperBound..<closeRange.lowerBound]))
        }
        // Try Liquid LFM 2.5 native <|tool_call_start|>...<|tool_call_end|>
        if let openRange = text.range(of: "<|tool_call_start|>", options: .caseInsensitive),
           let closeRange = text.range(of: "<|tool_call_end|>", options: .caseInsensitive, range: openRange.upperBound..<text.endIndex) {
            return parseWebSearchQuery(String(text[openRange.upperBound..<closeRange.lowerBound]))
        }
        return nil
    }

    static func parseWebSearchQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Try to find JSON object in the text (handles models that add extra text before JSON)
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let data = String(trimmed[jsonStart...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Name check (case-insensitive) — allow "web_search", "search", etc.
        if let name = json["name"] as? String,
           !name.lowercased().contains("search") { return nil }

        // Try nested dict arguments first
        if let args = json["arguments"] as? [String: Any],
           let q = args["query"] as? String, !q.isEmpty { return q }
        // Try string-encoded arguments
        if let argsStr = json["arguments"] as? String,
           let argsData = argsStr.data(using: .utf8),
           let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
           let q = argsDict["query"] as? String, !q.isEmpty { return q }
        // Try flat query key
        if let q = json["query"] as? String, !q.isEmpty { return q }
        return nil
    }

    /// Consumes a follow-up/retry inference stream (search fallback, grounding retry,
    /// empty-output retry, OpenELM retry) into accumulated text + thinking. All retry
    /// paths share this exact policy: batched UI flushes on `textDelta`, live thinking
    /// updates, and `.toolCall`/`.done` ignored (retries never re-enter the tool loop).
    /// Pass `streamsToUI: false` for lanes that only want the final text (OpenELM).
    func consumeFollowupStream(
        _ stream: AsyncStream<StreamEvent>,
        output: TurnOutput,
        clock: ContinuousClock,
        lastFlush: ContinuousClock.Instant,
        streamsToUI: Bool = true,
        updatesThinking: Bool = true
    ) async -> (text: String, thinking: String) {
        var accumulated = ""
        var thinkingAccumulated = ""
        var flush = lastFlush
        for await event in stream {
            if Task.isCancelled { break }
            switch event {
            case .textDelta(let chunk):
                accumulated += chunk
                guard streamsToUI else { break }
                let shouldFlush = clock.now - flush >= streamUpdateInterval
                    || chunk.contains(where: \.isNewline)
                    || accumulated.count <= 48
                if shouldFlush {
                    flush = clock.now
                    output.update(text: accumulated, persist: false)
                }
            case .thinkingDelta(let chunk):
                thinkingAccumulated += chunk
                guard updatesThinking else { break }
                output.update(thinking: thinkingAccumulated, duration: nil, persist: false)
            case .thinkingDone(let duration):
                guard updatesThinking else { break }
                output.update(thinking: thinkingAccumulated, duration: duration, persist: true)
            case .toolCall, .done:
                // Follow-up streams don't carry stats to persist (the primary
                // loop owns the final GenerationStats write).
                break
            }
        }
        return (accumulated, thinkingAccumulated)
    }

    /// Outcome of `runToolLoop`. The loop always finishes the generation itself
    /// (it owns the final re-invocation stream and writes the final text), so it
    /// returns the resolved text and a `finished` flag.
    struct ToolLoopOutcome {
        let finalText: String
        let finished: Bool
    }

    /// Executes one tool call, then re-invokes inference with the tool result, and
    /// loops if the model emits another tool call — bounded by `ToolRegistry.maxIterations`.
    /// Each iteration's tool result text is appended to the system prompt (web_search
    /// additionally carries its structured `searchContext` for the existing render path).
    /// Always returns `finished: true` — the caller should treat the turn as complete.
    func runToolLoop(
        toolName initialToolName: String,
        argsJSON initialArgsJSON: String,
        output: TurnOutput,
        model: InstalledModel,
        service: InferenceService,
        conversation: [ChatMessage],
        inferencePrompt: String,
        trimmedPrompt: String,
        effectiveImageData: Data?,
        baseSystemPrompt: String,
        toolContext: ToolContext,
        taskID: UUID,
        clock: ContinuousClock,
        lastFlush initialLastFlush: ContinuousClock.Instant
    ) async -> ToolLoopOutcome {
        var pendingToolName = initialToolName
        var pendingArgsJSON = initialArgsJSON
        var accumulatedToolResults: [ToolResult] = []
        var visibleToolActivities: [ChatToolActivity] = []
        var combinedSearchContext: SearchContext?
        var combinedCitations: [SearchCitation] = []

        // Agent trace: the model's conversation continues through the tool call so the
        // result appears as part of its own reasoning, NOT as a detached system-prompt
        // blob the model ignores. The original user question stays as the LAST history
        // turn; each tool result becomes the `prompt` (the latest user turn) on
        // re-invocation. This keeps strict user/assistant alternation that chat templates
        // (Qwen/Llama/Gemma/LFM) require — back-to-back user turns confuse them and the
        // model emits only <think> and no final answer.
        var traceConversation = conversation
        traceConversation.append(ChatMessage(role: .user, text: inferencePrompt))

        var iteration = 0
        while iteration < ToolRegistry.maxIterations {
            iteration += 1
            let toolName = pendingToolName
            let argsJSON = pendingArgsJSON
            chatEngineLogger.log("Tool loop iter \(iteration): dispatching \(toolName, privacy: .public)")

            let runningActivity = Self.toolActivity(
                name: toolName,
                output: Self.toolRunningOutput(for: toolName, argsJSON: argsJSON),
                model: model,
                status: .running,
                args: argsJSON
            )
            visibleToolActivities.append(runningActivity)
            output.setToolActivities(visibleToolActivities, persist: false)

            // Dispatch via the registry. Unknown names yield nil and are surfaced as an error.
            let toolStartTime = Date()
            let result = await ToolRegistry.dispatch(name: toolName, argsJSON: argsJSON, context: toolContext)
            let toolDuration = Date().timeIntervalSince(toolStartTime)

            guard let result = result else {
                chatEngineLogger.log("Unknown tool: \(toolName, privacy: .public)")
                // Replace the running row so the spinner doesn't persist forever.
                visibleToolActivities[visibleToolActivities.count - 1] = Self.toolActivity(
                    name: toolName,
                    output: "Unknown tool",
                    model: model,
                    status: .failed,
                    duration: toolDuration,
                    args: argsJSON
                )
                output.setToolActivities(visibleToolActivities, persist: true)
                output.appendNotice("⚠️ Unknown tool: \(toolName)")
                break
            }

            accumulatedToolResults.append(result)
            if let sc = result.searchContext { combinedSearchContext = sc }
            combinedCitations.append(contentsOf: result.citations)
            visibleToolActivities[visibleToolActivities.count - 1] = Self.toolActivity(from: result, model: model, duration: toolDuration, args: argsJSON)
            output.setToolActivities(visibleToolActivities, persist: true)
            output.setCitations(combinedCitations)

            if let directAnswer = Self.directToolAnswer(for: result, model: model) {
                output.finish(text: directAnswer, toolActivities: nil, stats: nil, duration: nil)
                return ToolLoopOutcome(finalText: directAnswer, finished: true)
            }

            // Build the continuation prompt FROM the tool result. This becomes the
            // latest user turn, giving clean alternation: ...history, user(question),
            // user(tool result + "answer now"). Bounded to respect small context windows.
            let isFinalIteration = iteration >= ToolRegistry.maxIterations
            let boundedOutput = Self.boundToolOutputForContext(result.output, model: model)
            let continuationPrompt = isFinalIteration
                ? "[Tool \(result.toolName) returned]: \(boundedOutput)\n\nYou have reached the tool-call limit. Using the result above, answer the user's original question now. Do not call any more tools."
                : "[Tool \(result.toolName) returned]: \(boundedOutput)\n\nUsing the result above, answer the user's original question. Only call another tool if the result is truly insufficient."

            chatEngineLogger.log("Tool \(toolName, privacy: .public) completed — re-invoking inference with trace (iter \(iteration))")

            // Re-invoke inference. The tool result IS the prompt (latest user turn); the
            // question lives at the end of `traceConversation` as the prior user turn.
            // web_search also passes its structured searchContext for the existing render path.
            let newStream: AsyncStream<StreamEvent>
            do {
                let genResult = try await service.generateStream(
                    prompt: continuationPrompt,
                    model: model,
                    conversation: traceConversation,
                    searchContext: combinedSearchContext,
                    systemPrompt: baseSystemPrompt,
                    imageData: effectiveImageData,
                    settings: store.settings
                )
                newStream = genResult.stream
            } catch {
                chatEngineLogger.log("Re-invocation failed: \(error.localizedDescription, privacy: .public) — ending tool loop")
                output.appendNotice("⚠️ \(error.localizedDescription)")
                break
            }

            // Consume the new stream. A `.toolCall` here means the model wants another tool.
            var accumulated = ""
            var thinkingAccumulated = ""
            var sawToolCall = false
            var nextToolName = ""
            var nextArgsJSON = ""
            var lastFlush = initialLastFlush
            var capturedStats: GenerationStats?

            let genStartTime = Date()
            for await newEvent in newStream {
                if Task.isCancelled { break }
                switch newEvent {
                case .textDelta(let chunk):
                    accumulated += chunk
                    let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                        || chunk.contains(where: \.isNewline)
                        || accumulated.count <= 48
                    if shouldFlush {
                        lastFlush = clock.now
                        output.update(text: accumulated, persist: false)
                    }
                case .thinkingDelta(let chunk):
                    thinkingAccumulated += chunk
                    output.update(thinking: thinkingAccumulated, duration: nil, persist: false)
                case .thinkingDone(let dur):
                    output.update(thinking: thinkingAccumulated, duration: dur, persist: true)
                case .toolCall(let name, let args):
                    // Model wants another tool; keep updating the same assistant bubble.
                    sawToolCall = true
                    nextToolName = name
                    nextArgsJSON = args
                case .done(let stats):
                    // Stats from tool-loop re-invocation are captured but the
                    // outer runToolLoop writes the final duration below.
                    capturedStats = stats
                }
            }

            if !sawToolCall {
                // No further tool call — finalize the answer.
                let genDuration = Date().timeIntervalSince(genStartTime)
                let thinkingSeen = !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let finalText = searchAwareAssistantText(
                    from: accumulated,
                    prompt: trimmedPrompt,
                    thinkingSeen: thinkingSeen,
                    searchContext: combinedSearchContext
                )
                let visibleText = AssistantResponseFallback.isEmptyOutputMessage(finalText)
                    ? Self.fallbackToolAnswer(from: accumulatedToolResults, model: model)
                    : finalText
                output.finish(text: visibleText, toolActivities: nil, stats: capturedStats, duration: genDuration)
                return ToolLoopOutcome(finalText: visibleText, finished: true)
            }

            // Prepare for the next iteration. Fold the just-used tool result + the
            // assistant's tool-call into the trace so the next re-invocation keeps
            // clean alternation: user(tool result 1), assistant(<tool_call 2>),
            // then the next tool result becomes the new prompt.
            traceConversation.append(ChatMessage(role: .user, text: continuationPrompt))
            traceConversation.append(ChatMessage(role: .assistant, text: accumulated))
            pendingToolName = nextToolName
            pendingArgsJSON = nextArgsJSON
            if iteration >= ToolRegistry.maxIterations {
                chatEngineLogger.log("Tool loop hit maxIterations (\(ToolRegistry.maxIterations)) — stopping")
                output.appendNotice("⚠️ Reached the tool-call limit (\(ToolRegistry.maxIterations)). Answering with what I have.")
                let cappedText = cleanedDisplayedAssistantText(accumulated)
                let visibleText = cappedText.isEmpty
                    ? Self.fallbackToolAnswer(from: accumulatedToolResults, model: model)
                    : cappedText
                output.finish(text: visibleText, toolActivities: nil, stats: nil, duration: nil)
                return ToolLoopOutcome(finalText: visibleText, finished: true)
            }
        }

        // Reached only via an early `break` (unknown tool or failed re-invocation).
        // Write a final answer so the assistant bubble is never left empty.
        let abortedText = accumulatedToolResults.isEmpty
            ? AssistantResponseFallback.emptyOutputMessage(thinkingSeen: false)
            : Self.fallbackToolAnswer(from: accumulatedToolResults, model: model)
        output.finish(text: abortedText, toolActivities: nil, stats: nil, duration: nil)
        return ToolLoopOutcome(finalText: abortedText, finished: true)
    }

    /// Minimal prompt used to re-invoke inference after a tool result has been appended
    /// to the conversation trace. The model continues from the tool result in the trace;
    /// this just hands it the turn. Short on purpose to respect small context windows.
    static let continuationPrompt = "Continue using the tool result above, then answer the user."

    /// Bounds a tool's output text so it can't blow the context budget on small devices.
    ///
    /// Uses the same model-aware character budget as injected document passages.
    /// `InferenceBudget` is the single source of truth for prompt limits, and the old
    /// hardcoded tier switch ignored the model's actual context window — LiteRT-LM is
    /// clamped to 2048 tokens no matter how much RAM the device has.
    static func boundToolOutputForContext(_ output: String, model: InstalledModel) -> String {
        let cap = InferenceBudget.documentContextBudget(for: model)
        if output.count <= cap { return output }
        let end = output.index(output.startIndex, offsetBy: cap, limitedBy: output.endIndex) ?? output.endIndex
        return String(output[output.startIndex..<end]) + "\n…[truncated to fit device context]"
    }

    /// Deterministic tools already have the final answer. Showing the tool result
    /// directly prevents a second model pass from dropping or corrupting it.
    static func directToolAnswer(for result: ToolResult, model: InstalledModel) -> String? {
        switch result.toolName {
        case "calculate", "get_current_time", "get_device_info", "get_battery_level":
            return boundToolOutputForContext(result.output, model: model)
        default:
            return nil
        }
    }

    /// If a follow-up model pass produces only thinking or an empty answer, keep the
    /// user-visible turn useful by surfacing the actual tool result.
    static func fallbackToolAnswer(from results: [ToolResult], model: InstalledModel) -> String {
        let blocks = results.map { result in
            let bounded = boundToolOutputForContext(result.output, model: model)
            return "[\(result.toolName)]\n\(bounded)"
        }
        return blocks.joined(separator: "\n\n")
    }

    static func toolActivity(from result: ToolResult, model: InstalledModel, duration: Double? = nil, args: String? = nil) -> ChatToolActivity {
        toolActivity(
            name: result.toolName,
            output: result.output,
            model: model,
            status: result.output.localizedCaseInsensitiveContains("Error:") ? .failed : .completed,
            duration: duration,
            args: args
        )
    }

    static func toolActivity(
        name: String,
        output: String,
        model: InstalledModel,
        status: ChatToolActivity.Status,
        duration: Double? = nil,
        args: String? = nil
    ) -> ChatToolActivity {
        ChatToolActivity(
            name: name,
            displayName: toolDisplayName(for: name, status: status),
            output: boundToolOutputForContext(output, model: model),
            args: args,
            status: status,
            duration: duration
        )
    }

    static func toolDisplayName(for name: String, status: ChatToolActivity.Status = .completed) -> String {
        if status == .running {
            switch name.lowercased() {
            case "web_search": return "Searching web"
            case "calculate": return "Calculating"
            case "get_current_time": return "Reading time"
            case "get_device_info": return "Reading device info"
            case "get_battery_level": return "Reading battery"
            case "search_chats": return "Searching chats"
            case "read_document": return "Reading document"
            case "search_documents": return "Searching documents"
            default: return name.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }

        switch name.lowercased() {
        case "web_search": return "Searched web"
        case "calculate": return "Calculated"
        case "get_current_time": return "Read time"
        case "get_device_info": return "Read device info"
        case "get_battery_level": return "Read battery"
        case "search_chats": return "Searched chats"
        case "read_document": return "Read document"
        case "search_documents": return "Searched documents"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func toolRunningOutput(for name: String, argsJSON: String) -> String {
        switch name.lowercased() {
        case "web_search":
            if let query = WebSearchTool.extractQuery(argsJSON) {
                return query
            }
            return "Searching the web"
        case "calculate":
            return CalculateTool.extractExpression(argsJSON) ?? "Evaluating expression"
        case "get_current_time":
            return "Reading current date, time, and timezone"
        case "get_device_info":
            return "Reading local hardware and runtime facts"
        case "get_battery_level":
            return "Reading battery state"
        case "search_chats":
            return "Searching local chat history"
        case "read_document":
            return "Reading attached document"
        case "search_documents":
            return "Searching the document library"
        default:
            return ""
        }
    }

    static func toolStatusMessage(for name: String, argsJSON: String) -> String {
        switch name.lowercased() {
        case "web_search":
            if let q = WebSearchTool.extractQuery(argsJSON) { return "🔍 Searching: \(q)…" }
            return "🔍 Searching the web…"
        case "calculate":
            if let e = CalculateTool.extractExpression(argsJSON) { return "🧮 Calculating: \(e)" }
            return "🧮 Calculating…"
        case "search_chats":
            if let q = SearchHistoryTool.extractQuery(argsJSON) { return "📚 Searching chats: \(q)…" }
            return "📚 Searching your chats…"
        case "read_document":
            return "📄 Reading document…"
        case "search_documents":
            return "📚 Searching documents…"
        case "get_current_time":
            return "🕐 Getting the time…"
        case "get_device_info":
            return "📱 Reading device info…"
        case "get_battery_level":
            return "🔋 Checking battery…"
        default:
            return "🛠 Running \(name)…"
        }
    }
}
