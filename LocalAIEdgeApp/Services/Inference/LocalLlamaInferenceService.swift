import Foundation

struct LocalLlamaInferenceService: InferenceService {
    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> ChatMessage {
        guard model.catalogItem.runtimeType == .gguf else {
            throw InferenceServiceError.runtimeUnavailable("This model requires the MLX runtime.")
        }
        // GGUF runtime does not support vision — warn if user attached an image
        if imageData != nil {
            throw InferenceServiceError.runtimeUnavailable(
                "The llama.cpp runtime does not support image input. Switch to an MLX vision model (e.g. Gemma 3n E2B MLX) for image understanding."
            )
        }
        guard let modelPath = model.localPath else {
            throw InferenceServiceError.missingLocalModelFile
        }

        let chatTurns = PromptRenderer.buildChatTurns(
            systemPrompt: systemPrompt,
            conversation: conversation,
            searchContext: searchContext,
            latestPrompt: prompt,
            modelName: model.catalogItem.displayName
        )

        let fallbackPrompt = PromptRenderer.render(
            systemPrompt: systemPrompt,
            conversation: conversation,
            searchContext: searchContext,
            latestPrompt: prompt,
            modelName: model.catalogItem.displayName
        )

        let nCtx = DeviceCapabilityService.contextSize()
        let rawMax: Int32 = searchContext != nil ? 2048 : 1024
        let maxGeneratedTokens = min(rawMax, nCtx / 2)
        do {
            let response = try await LocalLlamaRuntime.shared.generate(
                chat: chatTurns,
                fallbackPrompt: fallbackPrompt,
                using: modelPath,
                maxGeneratedTokens: maxGeneratedTokens
            )
            return ChatMessage(
                role: .assistant,
                text: response.isEmpty ? AssistantResponseFallback.emptyOutput : response,
                citations: searchContext?.citations ?? []
            )
        } catch {
            throw InferenceServiceError.runtimeUnavailable(error.localizedDescription)
        }
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        guard model.catalogItem.runtimeType == .gguf else {
            throw InferenceServiceError.runtimeUnavailable("This model requires the MLX runtime.")
        }
        // GGUF runtime does not support vision — warn if user attached an image
        if imageData != nil {
            throw InferenceServiceError.runtimeUnavailable(
                "The llama.cpp runtime does not support image input. Switch to an MLX vision model for image understanding."
            )
        }
        guard let modelPath = model.localPath else {
            throw InferenceServiceError.missingLocalModelFile
        }

        let chatTurns = PromptRenderer.buildChatTurns(
            systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
            conversation: conversation,
            searchContext: searchContext,
            latestPrompt: prompt,
            modelName: model.catalogItem.displayName
        )

        let fallbackPrompt = PromptRenderer.render(
            systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
            conversation: conversation,
            searchContext: searchContext,
            latestPrompt: prompt,
            modelName: model.catalogItem.displayName
        )

        let nCtx = DeviceCapabilityService.contextSize()
        let rawMax: Int32 = searchContext != nil ? 2048 : 1024
        let maxGeneratedTokens = min(rawMax, nCtx / 2)
        let messageID = UUID()
        let rawStream = try await LocalLlamaRuntime.shared.generateStream(
            chat: chatTurns,
            fallbackPrompt: fallbackPrompt,
            using: modelPath,
            maxGeneratedTokens: maxGeneratedTokens
        )
        let processor = StreamProcessor(rawStream: rawStream)
        return (messageID: messageID, stream: await processor.process())
    }

    /// Appends tool call definition to system prompt for tool-calling models.
    private func effectiveSystemPrompt(_ base: String, model: InstalledModel) -> String {
        guard model.catalogItem.supportsToolCalling, !base.contains("## web_search") else { return base }
        return base + """

# Tools

You have access to the following tool. Call it when you need current or real-time information (news, scores, weather, prices, recent events).

## web_search
Search the web for up-to-date information.
Parameters: query (string) — the search query

To call it, output ONLY this block (no other text before the closing tag):
<tool_call>
{"name": "web_search", "arguments": {"query": "your search query here"}}
</tool_call>

Call it at most once. Do not call it for questions you can answer from your training data.
"""
    }
}

enum PromptRenderer {

    /// Build structured chat turns for use with `llama_chat_apply_template`.
    static func buildChatTurns(
        systemPrompt: String,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        latestPrompt: String,
        modelName: String
    ) -> [LocalLlamaChatTurn] {
        var systemContent = "\(systemPrompt)\nYou are running locally on-device using model \(modelName). Respond directly to the user's question. Do not hallucinate or fabricate information."

        if let searchContext {
            let snippets = searchSnippets(searchContext)
            systemContent += "\n\nWeb Search Results:\n\(snippets)"
        }

        let maxTokensForGeneration: Int32 = searchContext != nil ? 2048 : 1024
        let nCtx = DeviceCapabilityService.contextSize()
        let maxPromptTokens = max(256, Int(nCtx) - Int(maxTokensForGeneration) - 64)
        let fixedTokens = estimateTokens(systemContent) + estimateTokens(latestPrompt) + 128
        let historyBudget = maxPromptTokens - fixedTokens

        // Conversation is prior history only — current user prompt is NOT included.
        let eligibleMessages = conversation.filter {
            $0.role != .search &&
            $0.role != .system &&
            !AssistantResponseFallback.shouldSkipInHistory($0) &&
            !$0.text.contains("<tool_call>")
        }

        var historyTurns: [LocalLlamaChatTurn] = []
        var usedTokens = 0

        for message in eligibleMessages.reversed() {
            let role: String
            switch message.role {
            case .assistant: role = "assistant"
            case .user:      role = "user"
            case .system, .search: continue
            }
            let cost = estimateTokens(message.text)
            if usedTokens + cost > historyBudget { break }
            historyTurns.insert(LocalLlamaChatTurn(role: role, content: message.text), at: 0)
            usedTokens += cost
        }

        if usesGemmaTurnFormat(modelName) {
            // Gemma 2/3 templates use role "model" instead of "assistant"
            let gemmaTurns = historyTurns.map { turn in
                turn.role == "assistant"
                    ? LocalLlamaChatTurn(role: "model", content: turn.content)
                    : turn
            }
            return buildGemmaChatTurns(
                systemContent: systemContent,
                historyTurns: gemmaTurns,
                latestPrompt: latestPrompt
            )
        }

        // Gemma 4 uses native <start_of_turn>system which the hardcoded
        // LLM_CHAT_TEMPLATE_GEMMA handler in llama.cpp does NOT support
        // (it folds system into the first user turn — correct for Gemma 2/3
        // but wrong for Gemma 4). Returning empty turns forces the runtime
        // to use the hand-crafted fallback from renderGemma4FallbackPrompt()
        // which produces the correct native-system format.
        if isGemma4(modelName) {
            return []
        }

        var turns: [LocalLlamaChatTurn] = []
        turns.append(LocalLlamaChatTurn(role: "system", content: systemContent))
        turns.append(contentsOf: historyTurns)
        turns.append(LocalLlamaChatTurn(role: "user", content: latestPrompt))

        return turns
    }

    /// Legacy raw-text fallback prompt for models without a chat template.
    static func render(
        systemPrompt: String,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        latestPrompt: String,
        modelName: String
    ) -> String {
        var systemSection = "\(systemPrompt)\nYou are running locally on-device using model \(modelName). Respond directly to the user's question. Do not hallucinate or fabricate information."

        if let searchContext {
            let snippets = searchSnippets(searchContext)
            systemSection += "\n\nWeb Search Results:\n\(snippets)"
        }

        let maxTokensForGeneration: Int32 = searchContext != nil ? 2048 : 1024
        let nCtx = DeviceCapabilityService.contextSize()
        let maxPromptTokens = max(256, Int(nCtx) - Int(maxTokensForGeneration) - 64)
        let fixedTokens = estimateTokens(systemSection) + estimateTokens(latestPrompt) + 128
        let historyBudget = maxPromptTokens - fixedTokens

        // Conversation is prior history only — current user prompt is NOT included.
        let eligibleMessages = conversation.filter {
            $0.role != .search &&
            $0.role != .system &&
            !AssistantResponseFallback.shouldSkipInHistory($0) &&
            !$0.text.contains("<tool_call>")
        }
        var historyLines: [String] = []
        var usedTokens = 0

        for message in eligibleMessages.reversed() {
            let line: String
            switch message.role {
            case .assistant: line = "Assistant: \(message.text)"
            case .user:      line = "User: \(message.text)"
            case .system, .search: continue
            }
            let cost = estimateTokens(line)
            if usedTokens + cost > historyBudget { break }
            historyLines.insert(line, at: 0)
            usedTokens += cost
        }

        if usesGemmaTurnFormat(modelName) {
            return renderGemmaFallbackPrompt(
                systemSection: systemSection,
                conversation: eligibleMessages,
                latestPrompt: latestPrompt,
                historyBudget: historyBudget
            )
        }

        if isGemma4(modelName) {
            return renderGemma4FallbackPrompt(
                systemSection: systemSection,
                conversation: eligibleMessages,
                latestPrompt: latestPrompt,
                historyBudget: historyBudget
            )
        }

        var parts: [String] = [systemSection]
        if !historyLines.isEmpty {
            parts.append(historyLines.joined(separator: "\n"))
        }
        parts.append("User: \(latestPrompt)\nAssistant:")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    /// Gemma 4 uses standard system/user/assistant roles (not user/model like Gemma 2/3).
    private static func isGemma4(_ modelName: String) -> Bool {
        modelName.localizedCaseInsensitiveContains("gemma 4") ||
        modelName.localizedCaseInsensitiveContains("gemma-4") ||
        modelName.localizedCaseInsensitiveContains("gemma4")
    }

    private static func usesGemmaTurnFormat(_ modelName: String) -> Bool {
        modelName.localizedCaseInsensitiveContains("gemma") && !isGemma4(modelName)
    }

    private static func buildGemmaChatTurns(
        systemContent: String,
        historyTurns: [LocalLlamaChatTurn],
        latestPrompt: String
    ) -> [LocalLlamaChatTurn] {
        var turns: [LocalLlamaChatTurn] = []

        if let firstUserIndex = historyTurns.firstIndex(where: { $0.role == "user" }) {
            for (index, turn) in historyTurns.enumerated() {
                if index == firstUserIndex {
                    turns.append(
                        LocalLlamaChatTurn(
                            role: "user",
                            content: systemContent + "\n\n" + turn.content
                        )
                    )
                } else {
                    turns.append(turn)
                }
            }
        } else {
            turns.append(LocalLlamaChatTurn(role: "user", content: systemContent + "\n\n" + latestPrompt))
            return turns
        }

        turns.append(LocalLlamaChatTurn(role: "user", content: latestPrompt))
        return turns
    }

    /// Gemma 4 fallback: uses native system role + model role (not assistant).
    private static func renderGemma4FallbackPrompt(
        systemSection: String,
        conversation: [ChatMessage],
        latestPrompt: String,
        historyBudget: Int
    ) -> String {
        var retainedMessages: [ChatMessage] = []
        var usedTokens = 0

        for message in conversation.reversed() {
            let cost = estimateTokens(message.text)
            if usedTokens + cost > historyBudget { break }
            retainedMessages.insert(message, at: 0)
            usedTokens += cost
        }

        // Gemma 4 uses <|turn> / <turn|> tokens (NOT <start_of_turn> / <end_of_turn>)
        // See: https://huggingface.co/google/gemma-4-e2b-it tokenizer_config.json
        // Ref: https://unsloth.ai/docs/models/gemma-4
        var promptTurns: [String] = []
        promptTurns.append("<|turn>system\n\(systemSection)<turn|>")

        for message in retainedMessages {
            switch message.role {
            case .user:
                promptTurns.append("<|turn>user\n\(message.text)<turn|>")
            case .assistant:
                promptTurns.append("<|turn>model\n\(message.text)<turn|>")
            case .system, .search:
                continue
            }
        }

        promptTurns.append("<|turn>user\n\(latestPrompt)<turn|>")
        promptTurns.append("<|turn>model\n")
        return promptTurns.joined(separator: "\n")
    }

    private static func renderGemmaFallbackPrompt(
        systemSection: String,
        conversation: [ChatMessage],
        latestPrompt: String,
        historyBudget: Int
    ) -> String {
        var retainedMessages: [ChatMessage] = []
        var usedTokens = 0

        for message in conversation.reversed() {
            let cost = estimateTokens(message.text)
            if usedTokens + cost > historyBudget { break }
            retainedMessages.insert(message, at: 0)
            usedTokens += cost
        }

        var promptTurns: [String] = []
        var systemInjected = false

        for message in retainedMessages {
            switch message.role {
            case .user:
                let content = systemInjected ? message.text : "\(systemSection)\n\n\(message.text)"
                promptTurns.append("<start_of_turn>user\n\(content)<end_of_turn>")
                systemInjected = true
            case .assistant:
                promptTurns.append("<start_of_turn>model\n\(message.text)<end_of_turn>")
            case .system, .search:
                continue
            }
        }

        let latestUserTurn = systemInjected ? latestPrompt : "\(systemSection)\n\n\(latestPrompt)"
        promptTurns.append("<start_of_turn>user\n\(latestUserTurn)<end_of_turn>")
        promptTurns.append("<start_of_turn>model\n")
        return promptTurns.joined(separator: "\n")
    }

    private static func searchSnippets(_ searchContext: SearchContext) -> String {
        searchContext.snippets.prefix(5).enumerated().map { index, snippet in
            let cleaned = stripHTML(snippet)
            let truncated = cleaned.count > 300 ? String(cleaned.prefix(300)) + "..." : cleaned
            return "[\(index + 1)] \(truncated)"
        }.joined(separator: "\n")
    }

    static func estimateTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }

    static func stripHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}