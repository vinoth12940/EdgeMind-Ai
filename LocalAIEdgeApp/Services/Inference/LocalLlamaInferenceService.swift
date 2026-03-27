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

        let maxGeneratedTokens: Int32 = searchContext != nil ? 2048 : 1024
        do {
            let response = try await LocalLlamaRuntime.shared.generate(
                chat: chatTurns,
                fallbackPrompt: fallbackPrompt,
                using: modelPath,
                maxGeneratedTokens: maxGeneratedTokens
            )
            return ChatMessage(
                role: .assistant,
                text: response.isEmpty ? "The model finished without returning text. Try a shorter prompt or another model." : response,
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
    ) async throws -> (messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>) {
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

        let maxGeneratedTokens: Int32 = searchContext != nil ? 2048 : 1024
        let messageID = UUID()
        let citations = searchContext?.citations ?? []
        let stream = try await LocalLlamaRuntime.shared.generateStream(
            chat: chatTurns,
            fallbackPrompt: fallbackPrompt,
            using: modelPath,
            maxGeneratedTokens: maxGeneratedTokens
        )
        return (messageID, citations, stream)
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

        var turns: [LocalLlamaChatTurn] = []
        turns.append(LocalLlamaChatTurn(role: "system", content: systemContent))

        let maxTokensForGeneration: Int32 = searchContext != nil ? 2048 : 1024
        let nCtx = DeviceCapabilityService.contextSize()
        let maxPromptTokens = max(256, Int(nCtx) - Int(maxTokensForGeneration) - 64)
        let fixedTokens = estimateTokens(systemContent) + estimateTokens(latestPrompt) + 200
        let historyBudget = maxPromptTokens - fixedTokens

        var eligibleMessages = conversation.filter { $0.role != .search }
        if let last = eligibleMessages.last, last.role == .user, last.text == latestPrompt {
            eligibleMessages.removeLast()
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
        let fixedTokens = estimateTokens(systemSection) + estimateTokens(latestPrompt) + 200
        let historyBudget = maxPromptTokens - fixedTokens

        var eligibleMessages = conversation.filter { $0.role != .search }
        if let last = eligibleMessages.last, last.role == .user, last.text == latestPrompt {
            eligibleMessages.removeLast()
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

        var parts: [String] = [systemSection]
        if !historyLines.isEmpty {
            parts.append(historyLines.joined(separator: "\n"))
        }
        parts.append("User: \(latestPrompt)\nAssistant:")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Helpers

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