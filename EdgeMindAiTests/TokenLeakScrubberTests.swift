import XCTest
@testable import EdgeMindAi

final class TokenLeakScrubberTests: XCTestCase {

    func test_passesBenignText() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let out = await scrubber.feed("Hello world")
        XCTAssertEqual(out, "Hello world")
        let flushed = await scrubber.flush()
        XCTAssertEqual(flushed, "")
    }

    func test_stripsKnownLeakToken() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let out = await scrubber.feed("Hello<|im_end|> world")
        XCTAssertEqual(out, "Hello world")
    }

    func test_holdsPartialLeakAcrossTokenBoundaries() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let a = await scrubber.feed("Hello<|im_")
        XCTAssertEqual(a, "Hello")
        let b = await scrubber.feed("end|> world")
        XCTAssertEqual(b, " world")
    }

    func test_benignAngleBracketPassesThrough() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let out = await scrubber.feed("2 < 3 and a > b")
        XCTAssertEqual(out, "2 < 3 and a > b")
    }

    func test_multipleLeaksInOneStream() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>", "<end_of_turn>"])
        let out = await scrubber.feed("one<|im_end|>two<end_of_turn>three")
        XCTAssertEqual(out, "onetwothree")
    }

    func test_flushReleasesHeldTail() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let a = await scrubber.feed("hi <|im_")
        XCTAssertEqual(a, "hi ")
        let flushed = await scrubber.flush()
        XCTAssertEqual(flushed, "<|im_")
    }

    func test_bufferGrowsWithLongestLeakToken() async {
        let long = "<|custom-long-end-of-turn-marker|>"
        let scrubber = TokenLeakScrubber(leakTokens: [long])
        let out = await scrubber.feed("before" + long + "after")
        XCTAssertEqual(out, "beforeafter")
    }
}
