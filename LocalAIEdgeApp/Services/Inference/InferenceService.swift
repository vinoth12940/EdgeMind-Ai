import Foundation

protocol InferenceService {
    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?
    ) async throws -> ChatMessage

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>)
}

enum InferenceServiceError: LocalizedError {
    case noModelInstalled
    case missingLocalModelFile
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noModelInstalled:
            return "Install a model before starting a chat."
        case .missingLocalModelFile:
            return "The selected model is marked installed, but its local file could not be found."
        case .runtimeUnavailable(let message):
            return message
        }
    }
}

enum AssistantResponseFallback {
    static let emptyOutput = "No visible answer was produced. Try a shorter prompt, turn off search, or switch models."
    static let emptyOutputAfterThinking = "The model reasoned, but it never produced a final answer. Try a shorter prompt, turn off search, or switch models."

    static func emptyOutputMessage(thinkingSeen: Bool) -> String {
        thinkingSeen ? emptyOutputAfterThinking : emptyOutput
    }

    static func isEmptyOutputMessage(_ text: String) -> Bool {
        text == emptyOutput || text == emptyOutputAfterThinking
    }

    static func shouldSkipInHistory(_ message: ChatMessage) -> Bool {
        message.role == .assistant && isEmptyOutputMessage(message.text)
    }

    static func isPromptEcho(_ response: String, prompt: String) -> Bool {
        normalized(response) == normalized(prompt)
    }

    static func isSearchAccessRefusal(_ text: String) -> Bool {
        let normalized = normalized(text)
        let refusalPhrases = [
            "i don't have real-time access",
            "i do not have real-time access",
            "i don't have live access",
            "i do not have live access",
            "i don't have access to live",
            "i do not have access to live",
            "i can't access live",
            "i cannot access live",
            "i can't provide the exact current",
            "i cannot provide the exact current",
            "i can't provide the current",
            "i cannot provide the current"
        ]
        return refusalPhrases.contains(where: normalized.contains)
    }

    private static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum InferenceBudget {
    static func safeContextWindow(for model: InstalledModel) -> Int {
        let catalogContext = model.catalogItem.contextWindowTokenCount

        switch model.catalogItem.runtimeType {
        case .gguf:
            let deviceContext = Int(DeviceCapabilityService.contextSize())
            if catalogContext > 0 {
                return max(512, min(deviceContext, catalogContext))
            }
            return max(512, deviceContext)
        case .mlx:
            return max(4_096, catalogContext > 0 ? catalogContext : 8_192)
        }
    }

    static func maxGeneratedTokens(for model: InstalledModel, searchContext: SearchContext?) -> Int {
        let preferred = searchContext == nil ? 1_024 : 2_048
        let contextWindow = safeContextWindow(for: model)
        let hardCeiling = max(512, contextWindow - 256)
        return min(preferred, hardCeiling)
    }

    static func mlxHistoryBudget(for model: InstalledModel, searchContext: SearchContext?, maxGeneratedTokens: Int) -> Int {
        let contextWindow = safeContextWindow(for: model)
        let reservedPromptSpace = searchContext == nil ? 3_072 : 8_192
        return max(4_096, contextWindow - maxGeneratedTokens - reservedPromptSpace)
    }

    static func mlxSearchBudgetCharacters(for model: InstalledModel, maxGeneratedTokens: Int) -> Int {
        let contextWindow = safeContextWindow(for: model)
        let promptBudget = max(4_096, contextWindow - maxGeneratedTokens - 4_096)
        return min(36_000, max(12_000, promptBudget * 2))
    }
}

enum SearchGroundingGuidance {
    static let instructions = """
WEB SEARCH RESULTS ARE ALREADY PROVIDED ABOVE.
Treat them as current web data for this reply.
Do not say that you lack real-time, live, or current access.
If the exact answer is visible in DIRECT ANSWER or SOURCES, state it directly.
If the retrieved results only point to live pages but do not expose the exact value, say that the retrieved results do not show the exact value and summarize the most relevant live sources.
Cite sources as [1], [2], etc.
"""

    static func retrySystemPrompt(from base: String) -> String {
        """
\(base)

WEB SEARCH RESULTS ARE ALREADY INCLUDED IN THIS PROMPT.
Answer strictly from those retrieved results.
Do not say that you lack real-time, live, or current access.
If the exact value is not visible in the retrieved text, say that the retrieved results do not show the exact value and summarize the most relevant sources.
Cite sources as [1], [2], etc.
"""
    }
}

enum AssistantResponseSanitizer {
    static func clean(_ text: String) -> String {
        var cleaned = text

        let globalPatterns = [
            // <think> blocks are now extracted live during streaming — not stripped here
            "(?i)<end_of_turn>",
            "(?i)<start_of_turn>\\s*(model|user|system)?",
            "(?i)<\\|turn>\\s*(model|user|system)?",
            "(?i)<turn\\|>",
            "(?i)<\\|channel>\\s*(thought)?",
            "(?i)<channel\\|>",
            "(?i)<\\|think\\|>",
            "(?i)<\\|tool_call>",
            "(?i)<tool_call\\|>",
            "(?i)</?tool_call>",
            "(?i)<\\|eot_id\\|>",
            "(?i)<eot_id>",
            "(?i)<\\|end_of_text\\|>",
            "(?i)<\\|im_end\\|>",
            "(?i)<\\|assistant\\|>",
            "(?i)<\\|user\\|>",
            "(?i)<\\|system\\|>",
            "(?i)<\\|im_start\\|>(assistant|user|system)",
            "(?i)<\\|start_header_id\\|>(assistant|user|system)<\\|end_header_id\\|>",
            "(?i)<｜Assistant｜>",
            "(?i)<｜User｜>",
            "(?i)<｜System｜>",
            "(?i)</s>",
            "(?i)<s>",
            "(?i)<bos>",
            "(?i)<eos>",
            "(?i)\\[INST\\]",
            "(?i)\\[/INST\\]",
            "(?i)<<SYS>>",
            "(?i)<</SYS>>"
        ]

        for pattern in globalPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        let leadingPromptPatterns = [
            "(?is)^###\\s*System[\\s\\S]*?###\\s*Current User Request\\s*\\nUser:.*?\\nAssistant:\\s*",
            "(?is)^system\\s*:\\s*.*?assistant\\s*:\\s*"
        ]

        for pattern in leadingPromptPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Remove transcript echoes — only strip leading lines that look like
        // a continuation of the prompt template (User: / Assistant: at start of output).
        // Stop stripping once we encounter a non-echo line to preserve legitimate content.
        let lines = cleaned.components(separatedBy: .newlines)
        var strippingLeadingEchoes = true
        var filteredLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if strippingLeadingEchoes && (trimmed.hasPrefix("User:") || trimmed.hasPrefix("Assistant:")) {
                // Skip leading echo lines
                continue
            }
            strippingLeadingEchoes = false
            filteredLines.append(line)
        }
        cleaned = filteredLines.joined(separator: "\n")

        if let echoedTranscriptRange = cleaned.range(of: #"\s+User:\s+[\s\S]*$"#, options: .regularExpression) {
            cleaned.removeSubrange(echoedTranscriptRange)
        }

        cleaned = cleaned.replacingOccurrences(of: "^(assistant|model)\\s*:\\s*", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
