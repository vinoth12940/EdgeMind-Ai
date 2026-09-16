// LocalAIEdgeApp/Services/Tools/UpfrontToolDetector.swift
import Foundation

/// Detects when a local tool should run UPFRONT (before inference) for models that
/// cannot reliably emit `<tool_call>` blocks, and returns results to inject into the
/// system prompt. This is the non-tool-model equivalent of the agentic tool loop —
/// the app runs the tool, the model just reads the result.
///
/// Only LOCAL tools are auto-run here (calculate, get_current_time, get_device_info,
/// get_battery_level). web_search has its own upfront path (gated by Live Search),
/// and search_chats / read_document are intentionally NOT auto-triggered because
/// guessing intent for them is too noisy.
enum UpfrontToolDetector {

    /// True when the prompt clearly maps to a local device tool. Used to keep
    /// web-search defaults from hijacking time/device/battery/calculation prompts.
    static func canHandleLocally(prompt: String) -> Bool {
        let lowered = prompt.lowercased()
        return matchesTimeIntent(lowered)
            || matchesDeviceIntent(lowered)
            || matchesBatteryIntent(lowered)
            || matchesDocumentIntent(lowered)
            || extractCalculationExpression(from: lowered, original: prompt) != nil
    }

    /// Inspect the user's prompt and run any local tools whose intent is clearly matched.
    /// Returns the concatenated results (ready for system-prompt injection), or nil if
    /// nothing fired.
    static func detectAndRun(prompt: String, context: ToolContext) async -> [ToolResult] {
        var results: [ToolResult] = []
        let lowered = prompt.lowercased()

        // get_current_time — "what time", "current date", "what day is it", "today's date"
        if matchesTimeIntent(lowered) {
            let r = await GetCurrentTimeTool().run(argsJSON: "{}", context: context)
            results.append(r)
        }

        // get_device_info — "what iphone", "what device", "how much memory", "what chip"
        if matchesDeviceIntent(lowered) {
            let r = await GetDeviceInfoTool().run(argsJSON: "{}", context: context)
            results.append(r)
        }

        // get_battery_level — "battery", "how much charge", "battery percentage"
        if matchesBatteryIntent(lowered) {
            let r = await GetBatteryLevelTool().run(argsJSON: "{}", context: context)
            results.append(r)
        }

        // search_documents — when the prompt refers to the user's library, OR is a
        // question the library could answer.
        //
        // The phrase list alone was far too narrow: for the 24 catalog models without
        // the tool loop this is the ONLY route to the library, so a natural question
        // ("What does the contract say about termination?") matched no phrase, no
        // search ran, and the model told the user to upload the document. Irrelevant
        // questions are still filtered, because a search with no matching terms
        // returns no hits and nothing is injected.
        if !isSocialOnly(prompt: prompt),
           matchesDocumentIntent(lowered) || looksLikeContentQuestion(lowered),
           context.settings.documentSearchEnabled,
           let index = context.documentSearchIndex,
           !index.isEmpty {
            let hits = DocumentSearchService.search(query: prompt, index: index)
            if !hits.isEmpty {
                let budget = context.installedModel.map { InferenceBudget.documentContextBudget(for: $0) } ?? 4_000
                results.append(ToolResult(
                    toolName: "search_documents",
                    output: DocumentSearchService.renderHits(hits, budgetCharacters: budget),
                    citations: hits.map(SearchDocumentsTool.citation(from:))
                ))
            }
        }

        // calculate — only when an explicit arithmetic expression is present.
        // "what is 47 * 89", "calculate 12 + 5", "sqrt(144)", "(10/2)+3"
        if let expr = extractCalculationExpression(from: lowered, original: prompt) {
            let r = await CalculateTool().run(
                argsJSON: "{\"expression\":\"\(expr)\"}",
                context: context
            )
            // Only include if it actually computed a value (not an error).
            if !r.output.hasPrefix("Error") {
                results.append(r)
            }
        }

        return results
    }

    /// Render the upfront results as a system-prompt block for the model to read.
    static func renderInjection(for results: [ToolResult]) -> String {
        guard !results.isEmpty else { return "" }
        let blocks = results.map { r in
            let bounded = String(r.output.prefix(800))
            return "[\(r.toolName)]: \(bounded)"
        }
        return """

        # Local device context
        The following information was just gathered from the device. Use it to answer the user's question accurately; do not claim you lack this information.

        \(blocks.joined(separator: "\n\n"))
        """
    }

    /// Some local tool results are the answer, not context for another model pass.
    /// Returning them directly avoids a non-tool model miscopying deterministic facts.
    static func directAnswer(for results: [ToolResult]) -> String? {
        guard results.count == 1, let result = results.first else { return nil }
        guard result.toolName == "calculate" else { return nil }
        guard !result.output.hasPrefix("Error") else { return result.output }

        if let value = result.output.removingPrefix("Result: ") {
            return "Result: \(value)"
        }
        return result.output
    }

    // MARK: - Social-prompt gate

    /// True when the prompt is purely social — a greeting, thanks, or small talk —
    /// and therefore needs no tools at all.
    ///
    /// `ToolRegistry.availableTools` advertises `calculate`, `get_current_time`,
    /// `get_device_info` and `get_battery_level` on every turn. Small models take
    /// that as an invitation and call `get_current_time`/`calculate` in response to
    /// "hi" instead of just replying, so the tool section is suppressed for turns
    /// that carry no real request.
    ///
    /// Deliberately conservative: anything carrying genuine intent
    /// ("hi, what time is it?", "hey can you search for X") falls through to the
    /// normal tool path.
    static func isSocialOnly(prompt: String) -> Bool {
        let normalized = prompt
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(separator: " ")
            .joined(separator: " ")
        guard !normalized.isEmpty, normalized.count <= 40 else { return false }

        // Never suppress tools when the prompt maps to a local tool.
        if canHandleLocally(prompt: prompt) { return false }

        if socialPhrases.contains(normalized) { return true }

        // A greeting followed only by filler ("hi there", "hello everyone",
        // "hey edge mind"). The remainder must be *entirely* filler, so
        // "hey can you help me" keeps its tools rather than being swallowed.
        let words = normalized.split(separator: " ").map(String.init)
        guard let first = words.first, greetingOpeners.contains(first) else { return false }
        let remainder = words.dropFirst()
        return remainder.allSatisfy { greetingFillers.contains($0) }
    }

    private static let greetingOpeners: Set<String> = [
        "hi", "hii", "hiii", "hey", "hello", "yo", "howdy", "hiya", "sup",
        "greetings", "thanks", "thx", "ty", "cheers"
    ]

    private static let greetingFillers: Set<String> = [
        "there", "you", "all", "everyone", "everybody", "guys", "team",
        "friend", "buddy", "mate", "edge", "mind", "ai", "again", "too"
    ]

    private static let socialPhrases: Set<String> = [
        "hi", "hii", "hiii", "hey", "hey there", "hello", "hello there", "yo",
        "howdy", "hiya", "sup", "greetings",
        "good morning", "good afternoon", "good evening", "good night",
        "thanks", "thank you", "thanks a lot", "thank you so much", "thx", "ty",
        "cheers", "ok", "okay", "k", "cool", "nice", "great", "awesome",
        "sounds good", "got it", "alright",
        "how are you", "how are you doing", "hows it going", "how is it going",
        "whats up", "what is up", "how have you been", "nice to meet you",
        "who are you", "what are you", "what can you do", "what do you do",
        "test", "testing"
    ]

    // MARK: - Intent matching (deliberately conservative to avoid false positives)

    private static func matchesTimeIntent(_ s: String) -> Bool {
        let keywords = ["what time", "current time", "what date", "current date",
                        "today's date", "todays date", "what day is", "day of the week",
                        "what's the date", "whats the date", "what's today", "whats today",
                        "current day", "right now", "is it today"]
        return keywords.contains { s.contains($0) }
    }

    private static func matchesDeviceIntent(_ s: String) -> Bool {
        let keywords = ["what iphone", "what device", "which iphone", "which device",
                        "what model", "what chip", "what processor", "how much memory",
                        "how much ram", "device info", "device information",
                        "my iphone", "my device", "what ios", "what version",
                        "capability tier", "what tier"]
        return keywords.contains { s.contains($0) }
    }

    private static func matchesDocumentIntent(_ s: String) -> Bool {
        let keywords = ["my document", "the document", "this document", "my documents",
                        "the pdf", "my pdf", "the attached file", "attached file",
                        "in the document", "in the pdf", "according to the document",
                        "in my notes", "from my notes", "in my files", "my library",
                        "the file i", "uploaded file"]
        return keywords.contains { s.contains($0) }
    }

    /// True when the prompt is a question or content request the on-device document
    /// library could plausibly answer, even without naming "document".
    ///
    /// Used ONLY to widen the document search. It deliberately does not feed
    /// `canHandleLocally`, which would otherwise suppress upfront web search for
    /// every question. Irrelevant questions cost nothing: a search with no matching
    /// terms returns no hits, so nothing is injected.
    private static func looksLikeContentQuestion(_ s: String) -> Bool {
        let words = s.split(separator: " ").map(String.init)
        guard words.count >= 3 else { return false }
        if s.contains("?") { return true }
        let openers: Set<String> = [
            "what", "how", "why", "when", "where", "which", "who", "whose",
            "can", "could", "does", "do", "did", "is", "are", "was", "were",
            "should", "would", "explain", "summarize", "summarise", "describe",
            "tell", "outline", "compare", "find", "show"
        ]
        guard let first = words.first else { return false }
        return openers.contains(first)
    }

    private static func matchesBatteryIntent(_ s: String) -> Bool {
        let keywords = ["battery", "how much charge", "charge level", "battery level",
                        "battery percentage", "how much battery", "battery life"]
        return keywords.contains { s.contains($0) }
    }

    /// Pulls an arithmetic expression out of a natural-language prompt.
    /// Conservative: requires at least one digit AND one operator to avoid firing on
    /// prose like "I have 3 apples". Tolerates "what is 47 * 89", "calculate 2+2",
    /// "sqrt(16)", "(10/2)+3".
    private static func extractCalculationExpression(from lowered: String, original: String) -> String? {
        // Strip common leading phrases to isolate the expression.
        let phrases = ["what is ", "whats ", "what's ", "calculate ", "compute ",
                       "evaluate ", "how much is ", "solve "]
        var working = lowered
        for phrase in phrases where working.hasPrefix(phrase) {
            working = String(working.dropFirst(phrase.count))
            break
        }
        // Also handle "what is X equal to" style by trimming trailing words.
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must contain at least one digit and one math operator.
        let hasDigit = working.contains { $0.isNumber }
        let operatorChars: Set<Character> = ["+", "-", "*", "/", "%", "^"]
        let hasOperator = working.contains { operatorChars.contains($0) }
        guard hasDigit, hasOperator else { return nil }

        // Reject if it's clearly a sentence ("I have 3 apples and 2 oranges")
        // by checking the expression is mostly math tokens.
        let mathish = working.filter { $0.isNumber || $0.isWhitespace || "()+-*/%.^,".contains($0) || "abcdefghijklmnopqrstuvwxyz".contains($0) }
        // Allow function names like sqrt, sin, max — so letters are permitted, but
        // the expression shouldn't have long word runs (prose).
        // Heuristic: no run of 4+ letters except known function names.
        let functions = ["sqrt", "abs", "round", "floor", "ceil", "sin", "cos",
                         "tan", "log", "ln", "min", "max", "pow"]
        var clean = working
        for f in functions {
            clean = clean.replacingOccurrences(of: f, with: String(repeating: " ", count: f.count))
        }
        // If there's still a run of 3+ letters after stripping function names, it's prose.
        if clean.range(of: "[a-zA-Z]{3,}", options: .regularExpression) != nil {
            return nil
        }

        // Use the ORIGINAL case (functions need lowercase anyway) but trimmed.
        // The MathEvaluator lowercases function names itself, so original is fine.
        var expr = original.trimmingCharacters(in: .whitespacesAndNewlines)
        for phrase in phrases where expr.lowercased().hasPrefix(phrase) {
            expr = String(expr.dropFirst(phrase.count))
            break
        }
        // Trim a trailing question mark.
        expr = expr.trimmingCharacters(in: CharacterSet(charactersIn: "? "))
        _ = mathish
        return expr.isEmpty ? nil : expr
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
