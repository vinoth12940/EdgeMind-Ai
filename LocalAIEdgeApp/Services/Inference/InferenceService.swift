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

    private static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
