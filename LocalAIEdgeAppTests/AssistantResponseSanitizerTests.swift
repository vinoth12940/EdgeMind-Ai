import XCTest
@testable import LocalAIEdgeApp

final class AssistantResponseSanitizerTests: XCTestCase {

    func test_stripsImEnd() {
        XCTAssertEqual(AssistantResponseSanitizer.clean("Hello world<|im_end|>"), "Hello world")
    }

    func test_stripsEndOfTurn() {
        XCTAssertEqual(AssistantResponseSanitizer.clean("Answer.<end_of_turn>"), "Answer.")
    }

    func test_stripsInst() {
        let cleaned = AssistantResponseSanitizer.clean("[INST]ignore[/INST] Result")
        XCTAssertFalse(cleaned.contains("[INST]"))
        XCTAssertFalse(cleaned.contains("[/INST]"))
    }

    func test_preservesBenignAngleBrackets() {
        let clean = "if a < b && b > c { return true }"
        XCTAssertEqual(AssistantResponseSanitizer.clean(clean), clean)
    }

    func test_defaultLeakTokensAreAllScrubbed() {
        let defaultLeaks = RuntimeProfile.safeMinimum(catalogID: UUID()).knownLeakTokens
        for token in defaultLeaks {
            let dirty = "OK" + token + " rest"
            let cleaned = AssistantResponseSanitizer.clean(dirty)
            XCTAssertFalse(cleaned.contains(token), "backstop missed token: \(token)")
        }
    }

    func test_instructionEchoDetection_matchesSystemPromptReplay() {
        let systemPrompt = "You are a helpful AI assistant. Answer the user's question directly and accurately. Be concise but thorough. Do not repeat the question back. Do not add unnecessary filler or disclaimers."
        let echoed = ", I'm a helpful AI assistant. Answer the user's question directly and accurately. Be concise but thorough. Do not repeat the question back. Do not add unnecessary filler or disclaimers."
        XCTAssertTrue(AssistantResponseFallback.isInstructionEcho(echoed, systemPrompt: systemPrompt))
    }

    func test_instructionEchoDetection_doesNotFlagNormalAnswer() {
        let systemPrompt = "You are a helpful AI assistant. Answer the user's question directly and accurately."
        let answer = "I am doing well, thanks for asking. How can I help you today?"
        XCTAssertFalse(AssistantResponseFallback.isInstructionEcho(answer, systemPrompt: systemPrompt))
    }
}
