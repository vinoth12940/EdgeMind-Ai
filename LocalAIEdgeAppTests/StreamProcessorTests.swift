import XCTest
@testable import LocalAIEdgeApp

final class StreamProcessorTests: XCTestCase {

    // Helper: feed tokens into StreamProcessor, collect all events
    private func process(tokens: [String]) async -> [StreamEvent] {
        let stream = AsyncStream<String> { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
        let processor = StreamProcessor(rawStream: stream)
        var events: [StreamEvent] = []
        for await event in await processor.process() {
            events.append(event)
        }
        return events
    }

    func test_plainText_passesThrough() async throws {
        let events = await process(tokens: ["Hello", " world"])
        // Expect one or more textDelta events whose text concatenates to "Hello world", then done
        let text = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(text, "Hello world")
        XCTAssertTrue(events.last.map { if case .done = $0 { return true }; return false } ?? false)
    }

    func test_thinkBlock_extracted() async throws {
        let events = await process(tokens: ["<think>", "pondering", "</think>", "answer"])
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(thinkText, "pondering")
        let answerText = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(answerText.contains("answer"))
        XCTAssertTrue(events.contains { if case .thinkingDone = $0 { return true }; return false })
    }

    func test_thinkingTag_extracted() async throws {
        let events = await process(tokens: ["<thinking>deep thought</thinking>answer"])
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(thinkText, "deep thought")
    }

    func test_reasoningTag_extracted() async throws {
        let events = await process(tokens: ["<reasoning>logic</reasoning>result"])
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(thinkText, "logic")
    }

    func test_thinkBlock_autoClosesOnStreamEnd() async throws {
        let events = await process(tokens: ["<think>", "incomplete"])
        XCTAssertTrue(events.contains { if case .thinkingDone = $0 { return true }; return false })
    }

    func test_mismatchedCloseTag_treatedAsText() async throws {
        // <think> open but </thinking> close — should NOT close the block
        let events = await process(tokens: ["<think>content</thinking>more"])
        // Block should auto-close at stream end, not at the mismatched tag
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(thinkText.contains("content"))
        XCTAssertTrue(thinkText.contains("</thinking>"))
    }

    func test_toolCall_emitted() async throws {
        let json = #"{"name":"web_search","query":"latest news"}"#
        let events = await process(tokens: ["<tool_call>", json, "</tool_call>"])
        XCTAssertTrue(events.contains {
            if case .toolCall(let name, _) = $0 { return name == "web_search" }; return false
        })
        // .done should NOT be emitted after a tool call (ChatView re-invokes)
        XCTAssertFalse(events.contains { if case .done = $0 { return true }; return false })
    }

    func test_toolCall_badJSON_flushedAsText() async throws {
        let events = await process(tokens: ["<tool_call>", "not json", "</tool_call>", "answer"])
        XCTAssertFalse(events.contains { if case .toolCall = $0 { return true }; return false })
        let text = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(text.contains("not json"))
    }

    func test_toolCall_streamEndBeforeClose_flushedAsText() async throws {
        let events = await process(tokens: ["<tool_call>", "partial"])
        XCTAssertFalse(events.contains { if case .toolCall = $0 { return true }; return false })
        let text = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(text.contains("partial"))
    }

    func test_secondToolCall_treatedAsText() async throws {
        let json2 = #"{"name":"web_search","query":"second"}"#
        // Feed two tool calls — both should produce text (bad JSON for first, guard for second)
        let events = await process(tokens: ["prefix <tool_call>", "bad", "</tool_call> <tool_call>", json2, "</tool_call>"])
        let toolEvents = events.filter { if case .toolCall = $0 { return true }; return false }
        // bad JSON means first fails; second should also fail (either bad or guard)
        XCTAssertEqual(toolEvents.count, 0)
    }
}
