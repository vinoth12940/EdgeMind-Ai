import XCTest
@testable import EdgeMindAi

/// Verifies the local chat-history search tool. This tool reads only the user's own
/// past sessions on-device — a flagship privacy-safe agentic capability.
final class SearchHistoryToolTests: XCTestCase {

    func test_findsMatchesAcrossSessions() async throws {
        let sessions = [
            ChatSession(title: "Trip planning", modelID: nil, messages: [
                ChatMessage(role: .user, text: "What's the weather in Tokyo?"),
                ChatMessage(role: .assistant, text: "Tokyo is warm this time of year.")
            ]),
            ChatSession(title: "Recipes", modelID: nil, messages: [
                ChatMessage(role: .user, text: "How do I make ramen?")
            ])
        ]
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: sessions,
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await SearchHistoryTool().run(argsJSON: "{\"query\": \"ramen\"}", context: ctx)
        XCTAssertTrue(result.output.contains("ramen"), "Got: \(result.output)")
        XCTAssertTrue(result.output.contains("Recipes"))
    }

    func test_returnsClearMessageWhenNoMatches() async throws {
        let sessions = [
            ChatSession(title: "Workout", modelID: nil, messages: [
                ChatMessage(role: .user, text: "pushups and squats")
            ])
        ]
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: sessions,
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await SearchHistoryTool().run(argsJSON: "{\"query\": \"quantum\"}", context: ctx)
        XCTAssertTrue(result.output.contains("No matches"), "Got: \(result.output)")
    }

    func test_emptyHistoryReturnsHelpfulMessage() async throws {
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await SearchHistoryTool().run(argsJSON: "{\"query\": \"anything\"}", context: ctx)
        XCTAssertTrue(result.output.contains("No past conversations"), "Got: \(result.output)")
    }

    func test_missingQueryArgumentReturnsErrorResult() async throws {
        // Need a non-empty history so the tool reaches the query-extraction guard
        // (empty history short-circuits with a "no conversations" message first).
        let session = ChatSession(title: "Anything", modelID: nil, messages: [
            ChatMessage(role: .user, text: "hello")
        ])
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [session],
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await SearchHistoryTool().run(argsJSON: "{}", context: ctx)
        XCTAssertTrue(result.output.contains("Error"), "Got: \(result.output)")
    }

    func test_excerptTruncatesLongMessages() {
        let longBody = String(repeating: "a", count: 500) + "NEEDLE" + String(repeating: "b", count: 500)
        let body = "x" + longBody + "y"
        guard let range = body.range(of: "NEEDLE") else {
            XCTFail("NEEDLE should be present"); return
        }
        let excerpt = SearchHistoryTool.excerpt(of: body, around: range)
        XCTAssertTrue(excerpt.contains("NEEDLE"))
        XCTAssertTrue(excerpt.contains("…"), "Long excerpts should be elided, got length \(excerpt.count)")
        // Bounded well below the full message length.
        XCTAssertLessThan(excerpt.count, body.count)
    }

    func test_extractQueryHandlesMultipleJSONShapes() {
        XCTAssertEqual(SearchHistoryTool.extractQuery("{\"query\": \"hello\"}"), "hello")
        XCTAssertEqual(SearchHistoryTool.extractQuery("{\"q\": \"hi\"}"), "hi")
        XCTAssertEqual(SearchHistoryTool.extractQuery("{\"keyword\": \"term\"}"), "term")
        XCTAssertEqual(SearchHistoryTool.extractQuery("bare query"), "bare query")
    }
}
