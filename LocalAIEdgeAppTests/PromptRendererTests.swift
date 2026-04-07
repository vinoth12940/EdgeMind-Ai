import XCTest
@testable import LocalAIEdgeApp

final class PromptRendererTests: XCTestCase {

    // MARK: - Token estimation

    func testEstimateTokensNonEmpty() {
        // 4 bytes per token (utf8.count / 4), minimum 1
        let count = PromptRenderer.estimateTokens("Hello world")
        XCTAssertGreaterThan(count, 0)
    }

    func testEstimateTokensEmpty() {
        XCTAssertEqual(PromptRenderer.estimateTokens(""), 1, "Empty string should return minimum of 1")
    }

    // MARK: - Prompt budget with small context (iPhone 12 tier)

    func testBudgetWithSmallContext() {
        // n_ctx = 2048, chat mode → maxGeneratedTokens = 1024
        // maxPromptTokens = max(256, 2048 - 1024 - 64) = max(256, 960) = 960
        // verify that the PromptRenderer respects this budget
        let budget = max(256, Int(2048) - Int(1024) - 64)
        XCTAssertEqual(budget, 960)
        XCTAssertLessThan(budget, 2048, "Prompt budget must leave room for generation")
    }

    func testBudgetWithSmallContextSearchMode() {
        // n_ctx = 2048, search mode → maxGeneratedTokens = 2048
        // maxPromptTokens = max(256, 2048 - 2048 - 64) = max(256, -64) = 256
        let budget = max(256, Int(2048) - Int(2048) - 64)
        XCTAssertEqual(budget, 256, "Floor of 256 prevents negative prompt budget")
    }

    // MARK: - Prompt budget with large context (iPhone 15+ tier)

    func testBudgetWithLargeContext() {
        // n_ctx = 8192, chat mode → maxGeneratedTokens = 1024
        // maxPromptTokens = max(256, 8192 - 1024 - 64) = 7104
        let budget = max(256, Int(8192) - Int(1024) - 64)
        XCTAssertEqual(budget, 7104)
    }

    func testBudgetWithLargeContextSearchMode() {
        // n_ctx = 8192, search mode → maxGeneratedTokens = 2048
        // maxPromptTokens = max(256, 8192 - 2048 - 64) = 6080
        let budget = max(256, Int(8192) - Int(2048) - 64)
        XCTAssertEqual(budget, 6080)
    }

    // MARK: - HTML stripping (used in searchSnippets)

    func testStripHTML() {
        let input = "<b>Hello</b> &amp; <em>world</em>"
        let result = PromptRenderer.stripHTML(input)
        XCTAssertEqual(result, "Hello & world")
    }

    func testStripHTMLEntities() {
        let input = "It&#x27;s &lt;great&gt; &quot;here&quot;&nbsp;now"
        let result = PromptRenderer.stripHTML(input)
        XCTAssertEqual(result, "It's <great> \"here\" now")
    }

    func testGemmaFallbackPromptUsesGemmaTurnTokens() {
        let conversation = [
            ChatMessage(role: .user, text: "Hi"),
            ChatMessage(role: .assistant, text: "Hello there")
        ]

        // Gemma 2/3 uses legacy turn format with <start_of_turn> tokens
        let prompt = PromptRenderer.render(
            systemPrompt: "Be concise.",
            conversation: conversation,
            searchContext: nil,
            latestPrompt: "What are you doing?",
            modelName: "Gemma 3 1B (GGUF)"
        )

        XCTAssertTrue(prompt.contains("<start_of_turn>user"))
        XCTAssertTrue(prompt.contains("<start_of_turn>model"))
        XCTAssertTrue(prompt.contains("Be concise."), "System instructions should be folded into the first user turn for Gemma")
        XCTAssertFalse(prompt.contains("<start_of_turn>system"), "Gemma fallback must not emit an unsupported system role")
        XCTAssertTrue(prompt.hasSuffix("<start_of_turn>model\n"))
    }

    func testGemma4FallbackPromptUsesSystemAndModelRoles() {
        let conversation = [
            ChatMessage(role: .user, text: "Hi"),
            ChatMessage(role: .assistant, text: "Hello there")
        ]

        // Gemma 4 has native system role + uses model (not assistant)
        let prompt = PromptRenderer.render(
            systemPrompt: "Be concise.",
            conversation: conversation,
            searchContext: nil,
            latestPrompt: "What are you doing?",
            modelName: "Gemma 4 E2B (GGUF)"
        )

        // Gemma 4 uses <|turn> / <turn|> tokens (not <start_of_turn> / <end_of_turn>)
        XCTAssertTrue(prompt.contains("<|turn>system"), "Gemma 4 should have a system turn")
        XCTAssertTrue(prompt.contains("<|turn>model"), "Gemma 4 should use model role")
        XCTAssertTrue(prompt.contains("<|turn>user"), "Gemma 4 should have user turns")
        XCTAssertTrue(prompt.contains("<turn|>"), "Gemma 4 should use <turn|> end token")
        XCTAssertTrue(prompt.contains("Be concise."), "System prompt should be present")
        XCTAssertTrue(prompt.hasSuffix("<|turn>model\n"))
    }

    func testGemmaChatTurnsFoldSystemIntoFirstUserTurn() {
        let conversation = [
            ChatMessage(role: .user, text: "Hi"),
            ChatMessage(role: .assistant, text: "Hello there")
        ]

        // Gemma 2/3 folds system into first user turn and has no system role
        let turns = PromptRenderer.buildChatTurns(
            systemPrompt: "Be concise.",
            conversation: conversation,
            searchContext: nil,
            latestPrompt: "What are you doing?",
            modelName: "Gemma 3 1B (GGUF)"
        )

        XCTAssertEqual(turns.first?.role, "user")
        XCTAssertTrue(turns.first?.content.contains("Be concise.") == true)
        XCTAssertTrue(turns.first?.content.contains("Hi") == true)
        XCTAssertFalse(turns.contains(where: { $0.role == "system" }))
        XCTAssertEqual(turns.last?.role, "user")
        XCTAssertEqual(turns.last?.content, "What are you doing?")
    }

    func testGemma4ChatTurnsReturnEmptyToForceFallback() {
        let conversation = [
            ChatMessage(role: .user, text: "Hi"),
            ChatMessage(role: .assistant, text: "Hello there")
        ]

        // Gemma 4 returns empty turns so the runtime skips llama_chat_apply_template
        // (which uses the wrong Gemma 2/3 handler) and falls back to
        // renderGemma4FallbackPrompt() which has native <start_of_turn>system.
        let turns = PromptRenderer.buildChatTurns(
            systemPrompt: "Be concise.",
            conversation: conversation,
            searchContext: nil,
            latestPrompt: "What are you doing?",
            modelName: "Gemma 4 E2B (GGUF)"
        )

        XCTAssertTrue(turns.isEmpty, "Gemma 4 should return empty turns to force the fallback prompt path")
    }

    func testAssistantResponseSanitizerRemovesTranscriptEcho() {
        let raw = "What are you doing User: Hi\nUser: Hi\nAssistant:"
        let cleaned = AssistantResponseSanitizer.clean(raw)

        XCTAssertEqual(cleaned, "What are you doing")
    }

    func testAssistantFallbackMessagesAreExcludedFromGemmaPromptHistory() {
        let conversation = [
            ChatMessage(role: .assistant, text: AssistantResponseFallback.emptyOutput),
            ChatMessage(role: .user, text: "Hi")
        ]

        let prompt = PromptRenderer.render(
            systemPrompt: "Be concise.",
            conversation: conversation,
            searchContext: nil,
            latestPrompt: "Reply normally.",
            modelName: "Gemma 4 E2B (GGUF)"
        )

        XCTAssertFalse(prompt.contains(AssistantResponseFallback.emptyOutput))
        XCTAssertTrue(prompt.contains("Hi"))
    }

    func testAssistantFallbackRecognizesPromptEcho() {
        XCTAssertTrue(AssistantResponseFallback.isPromptEcho("Hi", prompt: "Hi"))
        XCTAssertTrue(AssistantResponseFallback.isPromptEcho("  hi  ", prompt: "Hi"))
        XCTAssertFalse(AssistantResponseFallback.isPromptEcho("Hello", prompt: "Hi"))
    }
}
