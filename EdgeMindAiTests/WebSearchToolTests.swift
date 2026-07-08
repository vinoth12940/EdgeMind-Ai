import XCTest
@testable import EdgeMindAi

/// Verifies the web_search tool's query-extraction logic, which preserves the
/// published v0.1.0 behavior of tolerating several JSON shapes models emit.
/// We do not hit the network here — only the argument-parsing contract.
final class WebSearchToolTests: XCTestCase {

    func test_extractQueryNestedArguments() {
        let json = "{\"name\": \"web_search\", \"arguments\": {\"query\": \"weather today\"}}"
        XCTAssertEqual(WebSearchTool.extractQuery(json), "weather today")
    }

    func test_extractQueryStringEncodedArguments() {
        // Some models JSON-encode the arguments value as a string.
        let json = "{\"name\": \"web_search\", \"arguments\": \"{\\\"query\\\": \\\"stocks\\\"}\"}"
        XCTAssertEqual(WebSearchTool.extractQuery(json), "stocks")
    }

    func test_extractQueryFlatKey() {
        let json = "{\"name\": \"web_search\", \"query\": \"news headlines\"}"
        XCTAssertEqual(WebSearchTool.extractQuery(json), "news headlines")
    }

    func test_extractQueryBareStringFallback() {
        XCTAssertEqual(WebSearchTool.extractQuery("just a bare query"), "just a bare query")
    }

    func test_extractQueryReturnsNilForEmpty() {
        XCTAssertNil(WebSearchTool.extractQuery(""))
    }

    func test_extractQueryIgnoresEmptyQueryValue() {
        // An explicit empty query should not be treated as valid.
        let json = "{\"name\": \"web_search\", \"query\": \"\"}"
        XCTAssertNil(WebSearchTool.extractQuery(json))
    }

    func test_toolReturnsErrorWhenNoProviderConfigured() async throws {
        // Default settings have no provider/key — the tool must surface a clear
        // error result (not a crash) so the model can fall back to its own knowledge.
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await WebSearchTool().run(argsJSON: "{\"query\": \"test\"}", context: ctx)
        XCTAssertTrue(result.output.contains("Error") || result.output.contains("configured"),
                      "Expected an error/about-configured message, got: \(result.output)")
    }

    func test_toolReturnsErrorForMissingQuery() async throws {
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await WebSearchTool().run(argsJSON: "{}", context: ctx)
        XCTAssertTrue(result.output.contains("query") || result.output.contains("Error"),
                      "Got: \(result.output)")
    }
}
