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
        guard let modelPath = model.localPath else {
            throw InferenceServiceError.missingLocalModelFile
        }

        let renderedPrompt = PromptRenderer.render(
            systemPrompt: systemPrompt,
            conversation: conversation,
            searchContext: searchContext,
            latestPrompt: prompt,
            modelName: model.catalogItem.displayName
        )

        do {
            let response = try await LocalLlamaRuntime.shared.generate(prompt: renderedPrompt, using: modelPath)
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
        guard let modelPath = model.localPath else {
            throw InferenceServiceError.missingLocalModelFile
        }

        let renderedPrompt = PromptRenderer.render(
            systemPrompt: systemPrompt,
            conversation: conversation,
            searchContext: searchContext,
            latestPrompt: prompt,
            modelName: model.catalogItem.displayName
        )

        let messageID = UUID()
        let citations = searchContext?.citations ?? []
        let stream = try await LocalLlamaRuntime.shared.generateStream(prompt: renderedPrompt, using: modelPath)
        return (messageID, citations, stream)
    }
}

private enum PromptRenderer {
    /// Approximate token budget: n_ctx (8192) minus generation reserve (1024) minus safety margin.
    static let maxPromptTokens = 6800

    static func render(
        systemPrompt: String,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        latestPrompt: String,
        modelName: String
    ) -> String {
        // --- Fixed sections (always included) ---
        let systemSection = "### System\n\(systemPrompt)\nYou are running locally on-device using model \(modelName). Respond directly to the user's question. Do not hallucinate or fabricate information."

        var searchSection: String?
        if let searchContext {
            let snippets = searchContext.snippets.prefix(3).enumerated().map { index, snippet in
                let cleaned = Self.stripHTML(snippet)
                let truncated = cleaned.count > 300 ? String(cleaned.prefix(300)) + "..." : cleaned
                return "[\(index + 1)] \(truncated)"
            }.joined(separator: "\n")
            searchSection = "### Web Search Results\nAnswer the user's question using the search results below. Reference sources by number (e.g. [1], [2]) in your answer. If the results don't help, say so.\n\(snippets)"
        }

        let userSection = "### Current User Request\nUser: \(latestPrompt)\nAssistant:"

        // --- Calculate remaining budget for conversation history ---
        let fixedTokens = estimateTokens(systemSection)
            + estimateTokens(userSection)
            + (searchSection.map { estimateTokens($0) } ?? 0)
        let historyBudget = maxPromptTokens - fixedTokens

        // --- Fill history newest-first up to budget ---
        let eligibleMessages = conversation.filter { $0.role != .search }
        var historyLines: [String] = []
        var usedTokens = 0

        for message in eligibleMessages.reversed() {
            let line: String
            switch message.role {
            case .assistant: line = "Assistant: \(message.text)"
            case .user:      line = "User: \(message.text)"
            case .system:    line = "System: \(message.text)"
            case .search:    continue
            }
            let cost = estimateTokens(line)
            if usedTokens + cost > historyBudget { break }
            historyLines.insert(line, at: 0)
            usedTokens += cost
        }

        // --- Assemble ---
        var sections: [String] = [systemSection]
        if let s = searchSection { sections.append(s) }
        if !historyLines.isEmpty {
            sections.append("### Conversation\n\(historyLines.joined(separator: "\n\n"))")
        }
        sections.append(userSection)
        return sections.joined(separator: "\n\n")
    }

    /// Rough token estimate: ~4 UTF-8 bytes per token for most LLMs.
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