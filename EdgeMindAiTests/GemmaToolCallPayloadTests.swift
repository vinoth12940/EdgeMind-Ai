import XCTest
@testable import EdgeMindAi

/// Covers Gemma 4's native tool-call payload (`call:NAME{typed args}`) and locks
/// the invariant that every `ToolCallFormat` declared in RuntimeProfiles can
/// actually produce a `.toolCall` event through StreamProcessor.
final class GemmaToolCallPayloadTests: XCTestCase {

    // MARK: - Payload parser

    private func argsDict(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_stringArgument() throws {
        let parsed = try XCTUnwrap(GemmaToolCallPayload.parse(#"call:get_current_weather{location:<|"|>London<|"|>}"#))
        XCTAssertEqual(parsed.name, "get_current_weather")
        let args = try argsDict(parsed.argsJSON)
        XCTAssertEqual(args["location"] as? String, "London")
    }

    func test_typedScalarArguments() throws {
        let parsed = try XCTUnwrap(GemmaToolCallPayload.parse("call:configure{timeout:30, temperature:3.5, enabled:true, disabled:false}"))
        XCTAssertEqual(parsed.name, "configure")
        let args = try argsDict(parsed.argsJSON)
        XCTAssertEqual(args["timeout"] as? Int, 30)
        XCTAssertEqual(args["temperature"] as? Double, 3.5)
        XCTAssertEqual(args["enabled"] as? Bool, true)
        XCTAssertEqual(args["disabled"] as? Bool, false)
    }

    func test_stringListArgument() throws {
        let parsed = try XCTUnwrap(GemmaToolCallPayload.parse(#"call:lookup{cities:[<|"|>Paris<|"|>,<|"|>New York<|"|>]}"#))
        let args = try argsDict(parsed.argsJSON)
        XCTAssertEqual(args["cities"] as? [String], ["Paris", "New York"])
    }

    func test_stringContainingStructuralCharacters() throws {
        let parsed = try XCTUnwrap(GemmaToolCallPayload.parse(#"call:calculate{expression:<|"|>max(3, 9) + {2}:1<|"|>}"#))
        let args = try argsDict(parsed.argsJSON)
        XCTAssertEqual(args["expression"] as? String, "max(3, 9) + {2}:1")
    }

    func test_noArgumentCall() throws {
        let parsed = try XCTUnwrap(GemmaToolCallPayload.parse("call:get_current_time{}"))
        XCTAssertEqual(parsed.name, "get_current_time")
        XCTAssertEqual(try argsDict(parsed.argsJSON).count, 0)
    }

    func test_bareNameCallWithoutBraces() throws {
        let parsed = try XCTUnwrap(GemmaToolCallPayload.parse("call:get_battery_level"))
        XCTAssertEqual(parsed.name, "get_battery_level")
        XCTAssertEqual(try argsDict(parsed.argsJSON).count, 0)
    }

    func test_rejectsNonGemmaPayloads() {
        XCTAssertNil(GemmaToolCallPayload.parse(#"{"name":"web_search","arguments":{"query":"x"}}"#))
        XCTAssertNil(GemmaToolCallPayload.parse("just some text"))
        XCTAssertNil(GemmaToolCallPayload.parse("call:"))
        XCTAssertNil(GemmaToolCallPayload.parse("call:bad name with spaces{x:1}"))
    }

    func test_rejectsUnterminatedArgumentBlock() {
        XCTAssertNil(GemmaToolCallPayload.parse(#"call:web_search{query:<|"|>truncated"#))
    }

    // MARK: - Stream-level: every declared ToolCallFormat must yield .toolCall

    private func chunkStream(_ chunks: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    private func process(
        tokens: [String],
        activeThinkFormats: Set<ThinkFormat> = []
    ) async -> [StreamEvent] {
        let processor = StreamProcessor(
            rawStream: chunkStream(tokens),
            hangTimeout: 30,
            activeThinkFormats: activeThinkFormats
        )
        var events: [StreamEvent] = []
        for await event in await processor.process() {
            events.append(event)
        }
        return events
    }

    private func firstToolCall(_ events: [StreamEvent]) -> (name: String, argsJSON: String)? {
        for event in events {
            if case .toolCall(let name, let args) = event { return (name, args) }
        }
        return nil
    }

    func test_xmlToolCallFormat_yieldsToolCall() async throws {
        let events = await process(tokens: ["<tool_call>", #"{"name":"calculate","arguments":{"expression":"2+2"}}"#, "</tool_call>"])
        XCTAssertEqual(firstToolCall(events)?.name, "calculate")
    }

    func test_gemmaNativeToolCallFormat_yieldsToolCall() async throws {
        let events = await process(tokens: ["<|tool_call>", #"call:web_search{query:<|"|>IPL score today<|"|>}"#, "<tool_call|>"])
        let call = try XCTUnwrap(firstToolCall(events))
        XCTAssertEqual(call.name, "web_search")
        XCTAssertTrue(call.argsJSON.contains("IPL score today"))
    }

    func test_liquidToolCallFormat_yieldsToolCall() async throws {
        let events = await process(tokens: ["<|tool_call_start|>", #"{"name":"get_current_time","arguments":{}}"#, "<|tool_call_end|>"])
        XCTAssertEqual(firstToolCall(events)?.name, "get_current_time")
    }

    func test_gemmaThoughtBlockPrecedingToolCall_routesToThinkingThenToolCall() async throws {
        let events = await process(
            tokens: ["<|channel>thought\n", "The user wants live data, I should search.", "<channel|>", "<|tool_call>", #"call:web_search{query:<|"|>news<|"|>}"#, "<tool_call|>"],
            activeThinkFormats: [.gemmaChannel]
        )
        let thinking = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(thinking.contains("live data"))
        XCTAssertTrue(events.contains { if case .thinkingDone = $0 { return true }; return false })
        XCTAssertEqual(firstToolCall(events)?.name, "web_search")
    }

    func test_gemmaPayloadSplitAcrossChunks_stillParses() async throws {
        let events = await process(tokens: ["<|tool_call>", "call:calcul", "ate{expression:<|\"|>", "40+2", "<|\"|>}", "<tool_call|>"])
        let call = try XCTUnwrap(firstToolCall(events))
        XCTAssertEqual(call.name, "calculate")
        XCTAssertTrue(call.argsJSON.contains("40+2"))
    }
}
