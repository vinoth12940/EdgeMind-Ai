import XCTest
@testable import EdgeMindAi

/// Tests for `GenerationStats` carried on the terminal `.done(GenerationStats)`
/// event. Covers TTFT capture, delta counting, the done-event payload, and
/// think-block streams. These are the 0.3.0 plan's required stats tests.
final class GenerationStatsTests: XCTestCase {

    // MARK: - GenerationStats value semantics

    func test_tokensPerSecond_prefersExactTokenCount() {
        let stats = GenerationStats(totalDuration: 1.0, outputTokens: 12, deltaCount: 99)
        XCTAssertEqual(stats.tokensPerSecond ?? 0, 12.0, accuracy: 0.001)
        XCTAssertFalse(stats.isApproximate)
    }

    func test_tokensPerSecond_fallsBackToDeltaCount() {
        let stats = GenerationStats(totalDuration: 2.0, outputTokens: nil, deltaCount: 40)
        XCTAssertEqual(stats.tokensPerSecond ?? 0, 20.0, accuracy: 0.001)
        XCTAssertTrue(stats.isApproximate)
    }

    func test_tokensPerSecond_nilWhenNoTokensOrTooShort() {
        XCTAssertNil(GenerationStats(totalDuration: 1.0, outputTokens: 0, deltaCount: 0).tokensPerSecond)
        XCTAssertNil(GenerationStats(totalDuration: 0.01, outputTokens: 5, deltaCount: 5).tokensPerSecond)
    }

    // MARK: - StreamProcessor done-event payload

    func test_plainStream_doneCarriesDeltaCountAndDuration() async throws {
        // Newline-terminated chunks flush as separate deltas (the parser buffers
        // partial lines until a \n is seen, then flushes each complete line).
        let events = await process(tokens: ["Hello\n", " world\n"])

        let doneStats = try XCTUnwrap(statsFromDone(events))
        XCTAssertGreaterThanOrEqual(doneStats.deltaCount, 2, "two text deltas emitted")
        XCTAssertNotNil(doneStats.totalDuration)
        XCTAssertNotNil(doneStats.timeToFirstToken, "TTFT captured on first delta")
        XCTAssertNil(doneStats.outputTokens, "plain streams have no exact count")
    }

    func test_doneAfterSingleDelta_countsOne() async throws {
        let events = await process(tokens: ["solo"])
        let doneStats = try XCTUnwrap(statsFromDone(events))
        XCTAssertEqual(doneStats.deltaCount, 1)
    }

    func test_emptyStream_doneHasZeroDeltasAndNilTTFT() async throws {
        let events = await process(tokens: [])
        let doneStats = try XCTUnwrap(statsFromDone(events))
        XCTAssertEqual(doneStats.deltaCount, 0)
        XCTAssertNil(doneStats.timeToFirstToken, "no content → no first token")
    }

    func test_thinkBlockStream_thinkingDeltasAlsoCounted() async throws {
        let events = await process(tokens: ["<think>", "reasoning here", "</think>", "answer"])
        let doneStats = try XCTUnwrap(statsFromDone(events))
        // thinking deltas + the final answer delta are all counted as generation output
        XCTAssertGreaterThan(doneStats.deltaCount, 1)
        XCTAssertNotNil(doneStats.timeToFirstToken, "TTFT captured on first thinking delta")
    }

    func test_doneEvent_isTerminal() async throws {
        let events = await process(tokens: ["a", "b"])
        guard case .done = events.last else {
            XCTFail("expected .done as last event, got \(String(describing: events.last))")
            return
        }
    }

    // MARK: - ChatMessage Codable round-trip with stats

    func test_chatMessageWithStats_roundTripsThroughCodable() throws {
        let stats = GenerationStats(timeToFirstToken: 0.8, totalDuration: 2.4, outputTokens: 30, deltaCount: 28)
        var message = ChatMessage(role: .assistant, text: "hello")
        message.stats = stats

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.stats, stats)
    }

    func test_chatMessageWithoutStats_decodesBackwardCompatible() throws {
        // JSON produced by an older build (no `stats` key) must still decode.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","role":"assistant","text":"hi","createdAt":0,"citations":[],"attachments":[],"toolActivities":[]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ChatMessage.self, from: legacyJSON)
        XCTAssertNil(decoded.stats)
    }

    func test_chatMessageNilStats_roundTripsAsMissingKey() throws {
        var message = ChatMessage(role: .assistant, text: "hello")
        message.stats = nil

        let data = try JSONEncoder().encode(message)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("\"stats\""), "nil stats should not be encoded")

        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertNil(decoded.stats)
    }

    // MARK: - AppSettings.showGenerationStats default + migration

    func test_showGenerationStats_defaultsOn() {
        XCTAssertTrue(AppSettings.default.showGenerationStats)
    }

    func test_showGenerationStats_legacySettingsDecodeDefaultsOn() throws {
        let legacyJSON = """
        {"defaultModelID":null,"systemPrompt":"x","privacyModeEnabled":true,"useSearchByDefault":false,"voiceModeEnabled":false,"voiceModel":"Kokoro 82M","voicePreset":"Balanced","autoPlayVoiceResponses":false,"voiceResponseRate":1.0,"appearanceMode":"System","webSearchProvider":"None"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertTrue(decoded.showGenerationStats, "missing key must default to on")
    }

    // MARK: - Helpers

    /// Runs chunks through a v1 StreamProcessor and collects events.
    private func process(tokens: [String]) async -> [StreamEvent] {
        await process(tokens: tokens, v2Enabled: false)
    }

    private func process(tokens: [String], v2Enabled: Bool) async -> [StreamEvent] {
        let raw = AsyncStream<String> { continuation in
            for token in tokens {
                // Tiny sleep so wall-clock durations are meaningfully > 0.
                Thread.sleep(forTimeInterval: 0.002)
                continuation.yield(token)
            }
            continuation.finish()
        }
        let processor = StreamProcessor(rawStream: raw, v2Enabled: v2Enabled, hangTimeout: 5)
        var collected: [StreamEvent] = []
        for await event in await processor.process() {
            collected.append(event)
        }
        return collected
    }

    private func statsFromDone(_ events: [StreamEvent]) -> GenerationStats? {
        guard case .done(let stats) = events.last else { return nil }
        return stats
    }
}
