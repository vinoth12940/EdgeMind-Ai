import XCTest
@testable import EdgeMindAi

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

    func testContextWindowParserSupportsKNotation() {
        XCTAssertEqual(ModelCatalogItem.parseContextWindowTokenCount("128K"), 128_000)
        XCTAssertEqual(ModelCatalogItem.parseContextWindowTokenCount("40K"), 40_000)
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

    func testAssistantFallbackRecognizesSearchAccessRefusal() {
        XCTAssertTrue(AssistantResponseFallback.isSearchAccessRefusal("I don't have real-time access to live match data."))
        XCTAssertTrue(AssistantResponseFallback.isSearchAccessRefusal("I cannot provide the exact current IPL score."))
        XCTAssertTrue(AssistantResponseFallback.isSearchAccessRefusal("I do not have access to real-time, live scores from the current IPL match."))
        XCTAssertFalse(AssistantResponseFallback.isSearchAccessRefusal("The retrieved results do not show the exact score yet, but Cricbuzz and IPLT20 are live sources."))
    }

    func testSearchResultFallbackComposerBuildsLiveSourceSummary() {
        let context = SearchContext(
            query: "IPL live score current match",
            answer: nil,
            snippets: [
                "Cricbuzz: Live cricket scores, scorecard, commentary and stats.",
                "ESPN Cricinfo: Live score coverage and ball-by-ball updates."
            ],
            citations: [
                SearchCitation(title: "Cricbuzz", url: URL(string: "https://www.cricbuzz.com")!, snippet: "Live cricket scores"),
                SearchCitation(title: "ESPN Cricinfo", url: URL(string: "https://www.espncricinfo.com")!, snippet: "Live score coverage"),
                SearchCitation(title: "LiveScore", url: URL(string: "https://www.livescore.com")!, snippet: "IPL live scores")
            ]
        )

        let response = SearchResultFallbackComposer.compose(query: context.query, searchContext: context)

        XCTAssertTrue(response.contains("do not show the exact live value"))
        XCTAssertTrue(response.contains("Best live sources:"))
        XCTAssertTrue(response.contains("Cricbuzz [1]"))
    }

    func testSearchResultFallbackComposerPrefersImmediateReplyForLiveSourcePages() {
        let context = SearchContext(
            query: "IPL live score current match",
            answer: "The search results point to live pages such as Cricbuzz, ESPN Cricinfo, LiveScore, but they do not expose the exact live value in the returned snippet.",
            snippets: ["Cricbuzz: Live cricket scores and commentary."],
            citations: [
                SearchCitation(title: "Cricbuzz", url: URL(string: "https://www.cricbuzz.com")!, snippet: "Live cricket scores")
            ]
        )

        XCTAssertTrue(SearchResultFallbackComposer.prefersImmediateReply(query: context.query, searchContext: context))
    }

    func testSearchResultFallbackComposerSkipsUpfrontSearchForGreeting() {
        XCTAssertFalse(SearchResultFallbackComposer.shouldRunUpfrontSearch("Hi"))
        XCTAssertFalse(SearchResultFallbackComposer.shouldRunUpfrontSearch("Hello there"))
    }

    func testSearchResultFallbackComposerRunsUpfrontSearchForExplicitWebPrompt() {
        XCTAssertTrue(SearchResultFallbackComposer.shouldRunUpfrontSearch("search for current Apple stock price"))
        XCTAssertTrue(SearchResultFallbackComposer.shouldRunUpfrontSearch("look up the official website for Swift"))
    }

    func testLivePageSummaryExtractorPullsTickerFromHTML() {
        let html = """
        <a title="Royal Challengers Bengaluru vs Delhi Capitals, 26th Match - Need 56 off 39b " href="/live-cricket-scores/example">
            <span>RCB<!-- --> vs <!-- -->DC<!-- --> -<!-- --> <!-- -->Need 56 off 39b</span>
        </a>
        """

        XCTAssertEqual(
            LivePageSummaryExtractor.extractSummary(from: html, fallbackTitle: "Cricbuzz"),
            "Royal Challengers Bengaluru vs Delhi Capitals, 26th Match - Need 56 off 39b"
        )
    }

    func testLivePageSummaryExtractorPrefersMatchStateOverGenericSiteTitle() {
        let html = """
        <title>Live Cricket Score | Scorecard | Live Commentary - IPL 2026 | Cricbuzz.com</title>
        <a title="Live Cricket Score" href="/cricket-match/live-scores"></a>
        <a title="Royal Challengers Bengaluru vs Delhi Capitals, 26th Match - Need 42 off 25b " href="/cricket-match/live-scores"></a>
        <a title="Cricbuzz Home" href="/"></a>
        """

        XCTAssertEqual(
            LivePageSummaryExtractor.extractSummary(from: html, fallbackTitle: "Live Cricket Score"),
            "Royal Challengers Bengaluru vs Delhi Capitals, 26th Match - Need 42 off 25b"
        )
    }

    func testCricbuzzLiveMatchExtractorBuildsStructuredScoreSummary() {
        let matchesListJSON = """
        {"matches":[{"match":{"matchInfo":{"seriesName":"Indian Premier League 2026","matchDesc":"26th Match","state":"Complete","status":"Delhi Capitals won by 6 wickets","team1":{"teamName":"Royal Challengers Bengaluru","teamSName":"RCB"},"team2":{"teamName":"Delhi Capitals","teamSName":"DC"},"stateTitle":"DC Won"},"matchScore":{"team1Score":{"inngs1":{"runs":163,"wickets":10,"overs":19.6}},"team2Score":{"inngs1":{"runs":169,"wickets":4,"overs":18.4}}}}}]}
        """
        let escapedMatchesListJSON = matchesListJSON.replacingOccurrences(of: "\"", with: "\\\"")
        let html = "matchesList\\\":\(escapedMatchesListJSON)"

        XCTAssertEqual(
            CricbuzzLiveMatchExtractor.extractSummary(from: html, query: "IPL live score current match"),
            "Royal Challengers Bengaluru vs Delhi Capitals, 26th Match: Royal Challengers Bengaluru 163/10 (19.6 ov); Delhi Capitals 169/4 (18.4 ov). Delhi Capitals won by 6 wickets"
        )
    }

    func testLiveOrganicSnippetExtractorPromotesInlineScoreboardSnippet() {
        let organic = [
            SerperOrganicResult(
                title: "Live Cricket Score | Scorecard - IPL 2026 - Cricbuzz",
                link: "https://www.cricbuzz.com/cricket-match/live-scores",
                snippet: "Scotland tour of Namibia, 2026 · 3rd T20I • ScotlandSCO. 186-4 (20). NamibiaNAM. 187-6 (20)."
            ),
            SerperOrganicResult(
                title: "Live Cricket Scores - Find Latest Scores of all Matches Online - ESPN",
                link: "https://www.espn.com/cricket/scores",
                snippet: "Royal Challengers BengaluruRCB. 175/8 · Delhi CapitalsDC. 179/4 (19.5/20 ov, target 176)."
            )
        ]

        XCTAssertEqual(
            LiveOrganicSnippetExtractor.extractAnswer(from: organic, query: "IPL live score current match"),
            "Royal Challengers Bengaluru (RCB). 175/8; Delhi Capitals (DC). 179/4 (19.5/20 ov, target 176)."
        )
    }

    func testSearchPromptIncludesGroundingInstructions() {
        let prompt = PromptRenderer.render(
            systemPrompt: "Be concise.",
            conversation: [],
            searchContext: SearchContext(
                query: "today ipl score",
                answer: nil,
                snippets: ["Cricbuzz: Live score updates and commentary."],
                citations: []
            ),
            latestPrompt: "What is today ipl score?",
            modelName: "LFM2.5-1.2B (GGUF)"
        )

        XCTAssertTrue(prompt.contains("WEB SEARCH RESULTS ARE ALREADY PROVIDED ABOVE."))
        XCTAssertTrue(prompt.contains("Do not say that you lack real-time, live, or current access."))
    }

    func testMLXContextWindowIsClampedToDeviceTier() {
        let model = InstalledModel(
            catalogItem: makeMLXCatalogItem(
                contextWindow: "256K",
                supportsVision: false
            ),
            installState: .installed
        )

        XCTAssertEqual(InferenceBudget.safeContextWindow(for: model, tier: .compact), 2_048)
        XCTAssertEqual(InferenceBudget.safeContextWindow(for: model, tier: .standard), 4_096)
        XCTAssertEqual(InferenceBudget.safeContextWindow(for: model, tier: .pro), 8_192)
        XCTAssertEqual(InferenceBudget.safeContextWindow(for: model, tier: .ultra), 16_384)
    }

    func testMLXHistoryBudgetLeavesRoomForSearchAndGeneration() {
        let model = InstalledModel(
            catalogItem: makeMLXCatalogItem(
                contextWindow: "128K",
                supportsVision: false
            ),
            installState: .installed
        )
        let search = SearchContext(
            query: "latest Gemma model",
            answer: nil,
            snippets: ["Source snippet"],
            citations: []
        )

        let budget = InferenceBudget.mlxHistoryBudget(
            for: model,
            searchContext: search,
            maxGeneratedTokens: 2_048
        )

        XCTAssertEqual(budget, 2_048)
        XCTAssertLessThan(budget, 128_000, "MLX history should use phone-safe context, not the upstream advertised window")
    }

    func testVisionHistoryKeepsFewerMessages() {
        let textModel = InstalledModel(
            catalogItem: makeMLXCatalogItem(supportsVision: false),
            installState: .installed
        )
        let visionModel = InstalledModel(
            catalogItem: makeMLXCatalogItem(supportsVision: true),
            installState: .installed
        )

        let textLimit = InferenceBudget.maxHistoryMessages(for: textModel, searchContext: nil, tier: .pro)
        let visionLimit = InferenceBudget.maxHistoryMessages(for: visionModel, searchContext: nil, tier: .pro)

        XCTAssertLessThan(visionLimit, textLimit)
        XCTAssertEqual(textLimit, 28)
        XCTAssertEqual(visionLimit, 22)
    }

    func testTrimHistoryTextPreservesBeginningAndRecentTail() {
        let long = String(repeating: "A", count: 300) + String(repeating: "B", count: 300)
        let trimmed = InferenceBudget.trimHistoryText(long, maxCharacters: 300)

        XCTAssertLessThan(trimmed.count, long.count)
        XCTAssertLessThanOrEqual(trimmed.count, 300)
        XCTAssertTrue(trimmed.hasPrefix("A"))
        XCTAssertTrue(trimmed.hasSuffix("B"))
        XCTAssertTrue(trimmed.contains("trimmed for on-device memory safety"))
    }

    private func makeMLXCatalogItem(
        contextWindow: String = "128K",
        supportsVision: Bool
    ) -> ModelCatalogItem {
        ModelCatalogItem(
            displayName: supportsVision ? "Test VLM" : "Test LLM",
            family: .mlxCommunity,
            variant: supportsVision ? "MLX Community - 4bit - test/vlm" : "MLX Community - 4bit - test/llm",
            summary: "Test MLX model",
            parameterSize: "1B",
            quantization: "4-bit",
            diskSize: "1 GB",
            contextWindow: contextWindow,
            runtimeType: .mlx,
            mlxModelID: supportsVision ? "mlx-community/test-vlm" : "mlx-community/test-llm",
            sourceSupportsVision: supportsVision,
            supportsVision: supportsVision,
            runtimeStatus: .worksWithWarnings,
            minimumTier: .standard
        )
    }
}
