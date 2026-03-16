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
    ) async throws -> (messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>)
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

enum AssistantResponseSanitizer {
    static func clean(_ text: String) -> String {
        var cleaned = text

        let globalPatterns = [
            "(?is)<think>[\\s\\S]*?</think>",
            "(?i)<end_of_turn>",
            "(?i)<start_of_turn>\\s*(model|user|system)?",
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

        cleaned = cleaned.replacingOccurrences(of: "^(assistant|model)\\s*:\\s*", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
