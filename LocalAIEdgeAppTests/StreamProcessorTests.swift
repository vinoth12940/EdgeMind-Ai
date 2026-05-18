import XCTest
@testable import LocalAIEdgeApp

final class StreamProcessorTests: XCTestCase {

    // Helper: feed tokens into StreamProcessor, collect all events
    private func process(
        tokens: [String],
        v2Enabled: Bool = false,
        activeThinkFormats: Set<ThinkFormat> = []
    ) async -> [StreamEvent] {
        let stream = mockStream(chunks: tokens)
        let processor = StreamProcessor(
            rawStream: stream,
            v2Enabled: v2Enabled,
            hangTimeout: 30,
            activeThinkFormats: activeThinkFormats
        )
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

    func test_gemma4ToolCallFormat_emitted() async throws {
        // Gemma 4 uses <|tool_call> / <tool_call|> native format
        let json = #"{"name":"web_search","query":"weather today"}"#
        let events = await process(tokens: ["<|tool_call>", json, "<tool_call|>"])
        XCTAssertTrue(events.contains {
            if case .toolCall(let name, _) = $0 { return name == "web_search" }; return false
        })
        XCTAssertFalse(events.contains { if case .done = $0 { return true }; return false })
    }

    func test_gemma4ToolCallFormat_badJSON_flushedAsText() async throws {
        let events = await process(tokens: ["<|tool_call>", "garbage", "<tool_call|>", "answer"])
        XCTAssertFalse(events.contains { if case .toolCall = $0 { return true }; return false })
        let text = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(text.contains("garbage"))
    }

    func test_qwenNativeThinkFormat_extractedWhenActive() async throws {
        let events = await process(
            tokens: ["<|im_start|>think", "reasoning", "<|im_end|>", "final"],
            activeThinkFormats: [.qwenNative]
        )
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        let answerText = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(thinkText, "reasoning")
        XCTAssertTrue(answerText.contains("final"))
    }

    func test_gemmaChannelThinkFormat_acceptsNativeCloseToken() async throws {
        let events = await process(
            tokens: ["<|channel>thought\n", "reasoning", "<channel|>", "final"],
            activeThinkFormats: [.gemmaChannel]
        )
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        let answerText = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(thinkText, "reasoning")
        XCTAssertTrue(answerText.contains("final"))
    }

    func test_gemmaChannelThinkFormat_acceptsAlternateCloseToken() async throws {
        let events = await process(
            tokens: ["<|channel>thought\n", "reasoning", "<|channel>", "final"],
            activeThinkFormats: [.gemmaChannel]
        )
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        let answerText = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(thinkText, "reasoning")
        XCTAssertTrue(answerText.contains("final"))
    }

    func test_v2_stripsLeakTokensMidStream() async {
        let raw = mockStream(chunks: ["Hello<|im_", "end|> world"])
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: ["<|im_end|>"],
            v2Enabled: true,
            hangTimeout: 30,
            repetitionNgram: 6,
            repetitionCount: 3
        )
        let text = await collectText(await processor.process())
        XCTAssertEqual(text, "Hello world")
    }

    func test_v2_emptyStreamYieldsFallbackMessage() async {
        let raw = mockStream(chunks: [])
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: [],
            v2Enabled: true,
            hangTimeout: 1,
            repetitionNgram: 6,
            repetitionCount: 3
        )
        let text = await collectText(await processor.process())
        XCTAssertTrue(text.lowercased().contains("did not produce output"))
    }

    func test_v2_repetitionTrips() async {
        let phrase = "I think this is right. "
        let raw = mockStream(chunks: Array(repeating: phrase, count: 12))
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: [],
            v2Enabled: true,
            hangTimeout: 30,
            repetitionNgram: 6,
            repetitionCount: 3
        )
        let text = await collectText(await processor.process())
        XCTAssertLessThan(text.count, phrase.count * 12)
    }

    func test_v2_codeBlockSuppressesRepetitionGuard() async {
        let chunks = [
            "```swift\n",
            "for i in 0..<5 { print(i) }\n",
            "for i in 0..<5 { print(i) }\n",
            "for i in 0..<5 { print(i) }\n",
            "for i in 0..<5 { print(i) }\n",
            "```"
        ]
        let raw = mockStream(chunks: chunks)
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: [],
            v2Enabled: true,
            hangTimeout: 30,
            repetitionNgram: 6,
            repetitionCount: 3
        )
        let text = await collectText(await processor.process())
        XCTAssertTrue(text.contains("```"))
        XCTAssertTrue(text.contains("for i in 0..<5"))
    }

    func test_v2_unclosedCodeFenceKeepsGuardDisabledThroughEnd() async {
        let chunks = [
            "```swift\n",
            "print(\"a\")\n",
            "print(\"a\")\n",
            "print(\"a\")\n",
            "print(\"a\")\n",
            "print(\"a\")\n"
        ]
        let raw = mockStream(chunks: chunks)
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: [],
            v2Enabled: true,
            hangTimeout: 30,
            repetitionNgram: 4,
            repetitionCount: 2
        )
        let text = await collectText(await processor.process())
        let count = text.components(separatedBy: "print(\"a\")").count - 1
        XCTAssertEqual(count, 5)
    }

    func test_v2_guardReengagesAfterClosedFence() async {
        let prefix = "```swift\nlet x = 1\n```\n"
        let phrase = "I think this is right. "
        let raw = mockStream(chunks: [prefix] + Array(repeating: phrase, count: 12))
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: [],
            v2Enabled: true,
            hangTimeout: 30,
            repetitionNgram: 6,
            repetitionCount: 3
        )
        let text = await collectText(await processor.process())
        XCTAssertTrue(text.contains("```swift"))
        XCTAssertLessThan(text.count, prefix.count + phrase.count * 12)
    }

    func test_v2_disabledTogglePreservesV1Behavior() async {
        let raw = mockStream(chunks: ["Hello <|im_end|> world"])
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: ["<|im_end|>"],
            v2Enabled: false,
            hangTimeout: 1,
            repetitionNgram: 6,
            repetitionCount: 3
        )
        let text = await collectText(await processor.process())
        XCTAssertTrue(text.contains("<|im_end|>"))
    }

    func test_v2_hangWatchdogFiresOnSilentStream() async {
        let raw = AsyncStream<String> { continuation in
            Task {
                try? await Task.sleep(for: .seconds(2))
                continuation.finish()
            }
        }
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: [],
            v2Enabled: true,
            hangTimeout: 0.3,
            repetitionNgram: 6,
            repetitionCount: 3
        )
        let text = await collectText(await processor.process())
        XCTAssertTrue(text.lowercased().contains("did not produce output"))
    }

    func test_v2_hangWatchdogReArmsOnActivity() async {
        let raw = AsyncStream<String> { continuation in
            Task {
                for word in ["one ", "two ", "three ", "four "] {
                    try? await Task.sleep(for: .milliseconds(150))
                    continuation.yield(word)
                }
                continuation.finish()
            }
        }
        let processor = StreamProcessor(
            rawStream: raw,
            leakTokens: [],
            v2Enabled: true,
            hangTimeout: 0.3,
            repetitionNgram: 6,
            repetitionCount: 3
        )
        let text = await collectText(await processor.process())
        XCTAssertFalse(text.lowercased().contains("did not produce output"))
        XCTAssertTrue(text.contains("one"))
        XCTAssertTrue(text.contains("four"))
    }

    private func mockStream(chunks: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }

    private func collectText(_ events: AsyncStream<StreamEvent>) async -> String {
        var output = ""
        for await event in events {
            if case .textDelta(let text) = event {
                output += text
            }
        }
        return output
    }
}
