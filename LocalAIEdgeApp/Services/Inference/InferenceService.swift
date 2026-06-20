import Foundation

protocol InferenceService {
    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?,
        settings: AppSettings?
    ) async throws -> ChatMessage

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?,
        settings: AppSettings?
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
    static let instructionEcho = "The model repeated internal instructions instead of answering. Please resend your message or switch models."
    static let unreliableOpenELM = "OpenELM is not reliable enough for this app's chat runtime. Install and select Qwen 3 1.7B, Qwen 3.5 VL, or LFM2.5 instead."

    static func emptyOutputMessage(thinkingSeen: Bool) -> String {
        thinkingSeen ? emptyOutputAfterThinking : emptyOutput
    }

    static func isEmptyOutputMessage(_ text: String) -> Bool {
        text == emptyOutput || text == emptyOutputAfterThinking
    }

    static func isInstructionEchoMessage(_ text: String) -> Bool {
        text == instructionEcho
    }

    static func shouldSkipInHistory(_ message: ChatMessage) -> Bool {
        message.role == .assistant && (isEmptyOutputMessage(message.text) || isInstructionEchoMessage(message.text) || message.text == unreliableOpenELM)
    }

    static func isPromptEcho(_ response: String, prompt: String) -> Bool {
        normalized(response) == normalized(prompt)
    }

    static func isSearchAccessRefusal(_ text: String) -> Bool {
        let normalized = normalized(text)
        let refusalPhrases = [
            "i don't have real-time access",
            "i do not have real-time access",
            "i don't have access to real-time",
            "i do not have access to real-time",
            "i don't have live access",
            "i do not have live access",
            "i don't have access to live",
            "i do not have access to live",
            "i can't access live",
            "i cannot access live",
            "i can't access current",
            "i cannot access current",
            "i do not have access to current",
            "i can't provide the exact current",
            "i cannot provide the exact current",
            "i can't provide the current",
            "i cannot provide the current",
            "i cannot provide real-time",
            "i can't provide real-time",
            "i do not have access to live scores",
            "i don't have access to live scores",
            "i do not have access to live match data",
            "i don't have access to live match data"
        ]
        if refusalPhrases.contains(where: normalized.contains) {
            return true
        }

        let accessSignals = [
            "i don't have access",
            "i do not have access",
            "i can't access",
            "i cannot access",
            "i can't provide",
            "i cannot provide"
        ]
        let freshnessSignals = [
            "real-time",
            "realtime",
            "live",
            "current",
            "latest",
            "up-to-date"
        ]
        let groundingSignals = [
            "retrieved results",
            "search results",
            "sources above",
            "sources provided",
            "results do not show"
        ]

        return accessSignals.contains(where: normalized.contains)
            && freshnessSignals.contains(where: normalized.contains)
            && !groundingSignals.contains(where: normalized.contains)
    }

    static func isLikelyOffTopicReply(_ response: String, prompt: String) -> Bool {
        let p = normalized(prompt)
        let r = normalized(response)
        guard !p.isEmpty, !r.isEmpty else { return false }

        let stronglyOffTopicMarkers = [
            "subreddit",
            "let's say you have the following user message",
            "following user message",
            "user message:",
            "i've gotten quite a few messages",
            "whenever i play a level",
            "lurking for a while",
            "messages asking for help",
            "particular problem",
            "try my hand at answering",
            "answering them"
        ]
        if stronglyOffTopicMarkers.contains(where: r.contains) {
            return true
        }

        let greetingInputs: Set<String> = ["hi", "hello", "hey", "yo", "sup", "how are you", "how are you doing"]
        let responseWords = Set(
            r.components(separatedBy: .alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        let hasGreetingWord = responseWords.contains("hi")
            || responseWords.contains("hello")
            || responseWords.contains("hey")
        let hasGreetingPhrase = r.contains("doing well")
            || r.contains("how can i help")
            || r.contains("i am doing")
        if greetingInputs.contains(p) || p.hasPrefix("hi ") || p.hasPrefix("hello ") || p.hasPrefix("hey ") {
            return r.count > 180 || !(hasGreetingWord || hasGreetingPhrase)
        }

        if p.count <= 16 && r.count >= 220 {
            return true
        }

        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "and", "or", "not", "what", "who", "how", "when",
            "where", "which", "that", "this", "do", "does", "did", "will", "can", "could",
            "would", "should", "have", "has", "had", "be", "been", "being", "it", "its",
            "me", "my", "you", "your", "i", "am"
        ]
        let keywords = p
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        if !keywords.isEmpty {
            let overlap = keywords.filter { r.contains($0) }.count
            if overlap == 0 && r.count > 160 {
                return true
            }
        }

        return false
    }

    static func openELMSafeFallback(for prompt: String) -> String {
        let p = normalized(prompt)
        if p == "hi" || p == "hello" || p == "hey" || p == "how are you" || p == "how are you doing" {
            return "Hi! I am doing well. How can I help you?"
        }
        return "I could not produce a reliable short answer on OpenELM for that prompt. Please switch to Qwen 3 1.7B, Qwen 3.5 VL, or LFM2.5 for better quality."
    }

    static func isInstructionEcho(_ response: String, systemPrompt: String) -> Bool {
        let responseNormalized = normalized(response)
        let promptNormalized = normalized(systemPrompt)
        guard !responseNormalized.isEmpty, !promptNormalized.isEmpty else { return false }

        // Strong signal: response starts with a substantial prefix of system prompt.
        let promptPrefixCount = min(90, promptNormalized.count)
        if promptPrefixCount >= 40 {
            let promptPrefix = String(promptNormalized.prefix(promptPrefixCount))
            if responseNormalized.hasPrefix(promptPrefix) {
                return true
            }
        }

        // Heuristic markers from default safety/instruction prompts.
        let markerPhrases = [
            "answer the user's question directly and accurately",
            "be concise but thorough",
            "if you are unsure or do not know the answer",
            "do not repeat the question back",
            "do not add unnecessary filler or disclaimers"
        ]
        let promptMatches = markerPhrases.filter { promptNormalized.contains($0) }
        guard !promptMatches.isEmpty else { return false }

        let responseMatches = promptMatches.filter { responseNormalized.contains($0) }
        return responseMatches.count >= 2
    }

    private static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum OpenELMPromptTemplate {
    static func render(prompt: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Answer the question directly and concisely.

        Question: \(trimmedPrompt)
        Answer:
        """
    }
}

enum LFMPromptTemplate {
    static func render(systemPrompt: String, prompt: String) -> String {
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = ["<|startoftext|>"]
        if !system.isEmpty {
            parts.append("<|im_start|>system\n\(system)<|im_end|>\n")
        }
        parts.append("<|im_start|>user\n\(user)<|im_end|>\n")
        parts.append("<|im_start|>assistant\n")
        return parts.joined()
    }
}

enum SearchResultFallbackComposer {
    static func shouldRunUpfrontSearch(_ query: String) -> Bool {
        if queryLooksLive(query) {
            return true
        }

        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return false }

        let explicitSearchPhrases = [
            "search for",
            "look up",
            "lookup",
            "find online",
            "from the web",
            "on the web",
            "search online",
            "official source",
            "official website"
        ]

        return explicitSearchPhrases.contains(where: normalized.contains)
    }

    static func shouldReplace(_ text: String, prompt: String, searchContext: SearchContext) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.isEmpty
            || AssistantResponseFallback.isEmptyOutputMessage(text)
            || AssistantResponseFallback.isPromptEcho(text, prompt: prompt)
            || AssistantResponseFallback.isSearchAccessRefusal(text) {
            return true
        }
        return false
    }

    static func compose(query: String, searchContext: SearchContext) -> String {
        let isLiveQuery = queryLooksLive(query)
        let directAnswer = normalizedParagraph(searchContext.answer)
        let snippetSummary = summarizedSnippets(from: searchContext, liveQuery: isLiveQuery)
        let sourceSummary = summarizedSources(from: searchContext.citations, liveQuery: isLiveQuery)

        var sections: [String] = []

        if let directAnswer, !directAnswer.isEmpty {
            sections.append(directAnswer)
            if let snippetSummary,
               !directAnswer.lowercased().contains(snippetSummary.lowercased()) {
                sections.append(snippetSummary)
            }
        } else if isLiveQuery {
            sections.append("The retrieved web results do not show the exact live value in the returned snippets.")
            if let snippetSummary {
                sections.append(snippetSummary)
            }
        } else if let snippetSummary {
            sections.append(snippetSummary)
        } else {
            sections.append("The retrieved web results did not return a single direct answer, but the linked sources below are the most relevant matches.")
        }

        if !sourceSummary.isEmpty {
            sections.append(sourceSummary)
        }

        return sections.joined(separator: "\n\n")
    }

    static func prefersImmediateReply(query: String, searchContext: SearchContext) -> Bool {
        queryLooksLive(query)
            && (!searchContext.citations.isEmpty || normalizedParagraph(searchContext.answer) != nil)
    }

    static func queryLooksLive(_ query: String) -> Bool {
        let normalized = query.lowercased()
        let liveKeywords = [
            "live",
            "today",
            "now",
            "current",
            "latest",
            "score",
            "weather",
            "price",
            "breaking",
            "news",
            "stock",
            "match"
        ]

        return liveKeywords.contains(where: { normalized.contains($0) })
    }

    private static func normalizedParagraph(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func summarizedSnippets(from searchContext: SearchContext, liveQuery: Bool) -> String? {
        let cleaned = searchContext.snippets
            .map {
                $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else { return nil }

        if liveQuery {
            return "Returned snippets point to live score pages and match centers rather than exposing an inline scoreboard."
        }

        let summary = cleaned.prefix(2).joined(separator: " ")
        if summary.count > 320 {
            return String(summary.prefix(317)) + "..."
        }
        return summary
    }

    private static func summarizedSources(from citations: [SearchCitation], liveQuery: Bool) -> String {
        let sourceList = citations.prefix(liveQuery ? 4 : 3).enumerated().map { index, citation in
            "\(citation.title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)) [\(index + 1)]"
        }

        guard !sourceList.isEmpty else { return "" }
        let prefix = liveQuery ? "Best live sources:" : "Most relevant sources:"
        return "\(prefix) \(sourceList.joined(separator: ", "))."
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
        case .foundationModels:
            return max(4_096, catalogContext > 0 ? catalogContext : 4_096)
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
If DIRECT ANSWER already contains a scoreboard or live value, restate that value plainly instead of saying the sources are incomplete.
If DIRECT ANSWER already answers the user's question, keep the reply focused on that answer and skip unrelated results from other sources.
Lead with the answer instead of talking about search results or retrieved snippets.
Do not mention tool access, prompt context, or internal search steps unless the user asks.
If the retrieved results only point to live pages but do not expose the exact value, say that the retrieved results do not show the exact value and summarize the most relevant live sources.
Cite sources as [1], [2], etc.
"""

    static func retrySystemPrompt(from base: String) -> String {
        """
\(base)

WEB SEARCH RESULTS ARE ALREADY INCLUDED IN THIS PROMPT.
Answer strictly from those retrieved results.
Do not say that you lack real-time, live, or current access.
If DIRECT ANSWER already contains a scoreboard or live value, restate that value plainly instead of saying the sources are incomplete.
If DIRECT ANSWER already answers the user's question, keep the reply focused on that answer and skip unrelated results from other sources.
Lead with the answer instead of talking about search results or retrieved snippets.
Do not mention tool access, prompt context, or internal search steps unless the user asks.
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
            "(?i)<\\|tool_call_start>",
            "(?i)<\\|tool_call_end>",
            "(?i)<\\|tool_output>",
            "(?i)<tool_output\\|>",
            "(?i)</?tool_output>",
            "(?i)<\\|tool_output_start>",
            "(?i)<\\|tool_output_end>",
            "(?i)<\\|eot_id\\|>",
            "(?i)<eot_id>",
            "(?i)<\\|end_of_text\\|>",
            "(?i)<\\|endoftext\\|>",
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
