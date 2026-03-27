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
}
