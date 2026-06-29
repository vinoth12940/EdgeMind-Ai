import XCTest
@testable import EdgeMindAi

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

    func test_offTopicDetection_flagsLongIrrelevantReplyForHi() {
        let response = "I'm a newbie to this subreddit and I've been lurking for a while. Let's say you have the following user message and need to answer them."
        XCTAssertTrue(AssistantResponseFallback.isLikelyOffTopicReply(response, prompt: "Hi"))
    }

    func test_offTopicDetection_flagsObservedOpenELMTrainingContinuation() {
        let response = "I'm a newbie to this subreddit, and I've been lurking for a while. I've gotten quite a few messages asking for help with a particular problem, so I thought I'd try my hand at answering them."
        XCTAssertTrue(AssistantResponseFallback.isLikelyOffTopicReply(response, prompt: "What are you doing?"))
    }

    func test_offTopicDetection_flagsGreetingEchoInsidePromptTemplateContinuation() {
        let response = "Let's say you have the following user message:\n\nHi, I'm having a really weird issue with my game."
        XCTAssertTrue(AssistantResponseFallback.isLikelyOffTopicReply(response, prompt: "Hi"))
    }

    func test_offTopicDetection_allowsSimpleGreetingReply() {
        let response = "Hi! I am doing well. How can I help you?"
        XCTAssertFalse(AssistantResponseFallback.isLikelyOffTopicReply(response, prompt: "Hi"))
    }

    func test_openELMSafeFallback_forGreeting() {
        XCTAssertEqual(
            AssistantResponseFallback.openELMSafeFallback(for: "Hi"),
            "Hi! I am doing well. How can I help you?"
        )
    }

    func test_openELMPromptTemplate_usesPlainCompletionPrompt() {
        XCTAssertEqual(
            OpenELMPromptTemplate.render(prompt: " Hi \n"),
            """
            Answer the question directly and concisely.

            Question: Hi
            Answer:
            """
        )
    }

    func test_lfmPromptTemplate_usesChatMLFormat() {
        XCTAssertEqual(
            LFMPromptTemplate.render(systemPrompt: "Be brief.", prompt: " Hi \n"),
            "<|startoftext|><|im_start|>system\nBe brief.<|im_end|>\n<|im_start|>user\nHi<|im_end|>\n<|im_start|>assistant\n"
        )
    }
}
