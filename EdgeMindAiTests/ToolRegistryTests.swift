import XCTest
@testable import EdgeMindAi

/// Verifies the registry gates tools correctly per turn, renders the prompt section,
/// and routes dispatch to the right tool.
final class ToolRegistryTests: XCTestCase {

    // MARK: - availableTools gating

    func test_allToolsHaveStableNames() {
        let names = ToolRegistry.allTools.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count, "Tool names must be unique")
        // Core tools are always present.
        XCTAssertNotNil(ToolRegistry.allTools.first { $0.name == "calculate" })
        XCTAssertNotNil(ToolRegistry.allTools.first { $0.name == "get_current_time" })
        XCTAssertNotNil(ToolRegistry.allTools.first { $0.name == "get_device_info" })
        XCTAssertNotNil(ToolRegistry.allTools.first { $0.name == "get_battery_level" })
    }

    func test_searchHistoryToolOmittedWhenNoSessions() {
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let tools = ToolRegistry.availableTools(context: ctx)
        XCTAssertNil(tools.first { $0.name == "search_chats" }, "search_chats must be absent with no history")
        // But always-on tools are still present.
        XCTAssertNotNil(tools.first { $0.name == "calculate" })
    }

    func test_searchHistoryToolPresentWhenSessionsExist() {
        let session = ChatSession(title: "Hello", modelID: nil, messages: [
            ChatMessage(role: .user, text: "hi there")
        ])
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [session],
            attachedDocuments: [],
            installedModel: nil
        )
        let tools = ToolRegistry.availableTools(context: ctx)
        XCTAssertNotNil(tools.first { $0.name == "search_chats" })
    }

    func test_readDocumentToolOmittedWhenNoDocuments() {
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let tools = ToolRegistry.availableTools(context: ctx)
        XCTAssertNil(tools.first { $0.name == "read_document" })
    }

    func test_readDocumentToolPresentWhenDocumentAttached() {
        let doc = ChatAttachment(kind: .pdf, fileName: "report.pdf", mimeType: "application/pdf")
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [doc],
            installedModel: nil
        )
        let tools = ToolRegistry.availableTools(context: ctx)
        XCTAssertNotNil(tools.first { $0.name == "read_document" })
    }

    func test_webSearchOmittedWhenNoProviderConfigured() {
        // Default settings have no API key and provider is .none → no gateway.
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let tools = ToolRegistry.availableTools(context: ctx)
        XCTAssertNil(tools.first { $0.name == "web_search" }, "web_search must be absent without a configured provider")
    }

    // MARK: - Prompt section rendering

    func test_renderPromptSectionEmptyForNoTools() {
        XCTAssertTrue(ToolRegistry.renderPromptSection(for: []).isEmpty)
    }

    func test_renderPromptSectionIncludesAllToolNames() {
        let tools: [Tool] = [CalculateTool(), GetCurrentTimeTool()]
        let section = ToolRegistry.renderPromptSection(for: tools)
        XCTAssertTrue(section.contains("# Tools"))
        XCTAssertTrue(section.contains("## calculate"))
        XCTAssertTrue(section.contains("## get_current_time"))
        XCTAssertTrue(section.contains("<tool_call>"))
        XCTAssertTrue(section.contains("\"name\": \"tool_name\""))
    }

    // MARK: - Dispatch

    func test_dispatchRoutesToCorrectTool() async throws {
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await ToolRegistry.dispatch(
            name: "calculate",
            argsJSON: "{\"expression\": \"6 * 7\"}",
            context: ctx
        )
        let r = try XCTUnwrap(result)
        XCTAssertEqual(r.toolName, "calculate")
        XCTAssertTrue(r.output.contains("42"))
    }

    func test_dispatchReturnsNilForUnknownTool() async {
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await ToolRegistry.dispatch(name: "nonexistent_tool", argsJSON: "{}", context: ctx)
        XCTAssertNil(result, "Unknown tools must yield nil, not an error result")
    }

    func test_dispatchIsCaseInsensitive() async throws {
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await ToolRegistry.dispatch(name: "CALCULATE", argsJSON: "{\"expression\": \"1 + 1\"}", context: ctx)
        let r = try XCTUnwrap(result)
        XCTAssertEqual(r.toolName, "calculate")
    }

    // MARK: - maxIterations contract

    func test_maxIterationsIsBounded() {
        // The loop cap must be a small, sensible number — not unbounded.
        XCTAssertLessThanOrEqual(ToolRegistry.maxIterations, 5)
        XCTAssertGreaterThanOrEqual(ToolRegistry.maxIterations, 1)
    }

    // MARK: - Upfront local intent detection

    func test_upfrontDetectorHandlesDeviceTimeLocally() {
        XCTAssertTrue(UpfrontToolDetector.canHandleLocally(prompt: "What is the current time and date on this device?"))
        XCTAssertTrue(SearchResultFallbackComposer.shouldRunUpfrontSearch("What is the current time and date on this device?"))
    }

    func test_upfrontDetectorHandlesCalculationLocally() {
        XCTAssertTrue(UpfrontToolDetector.canHandleLocally(prompt: "Calculate 47 * 89"))
    }

    func test_webPromptStillNeedsSearchWhenNoLocalToolMatches() {
        let prompt = "What is the latest Apple stock price?"
        XCTAssertFalse(UpfrontToolDetector.canHandleLocally(prompt: prompt))
        XCTAssertTrue(SearchResultFallbackComposer.shouldRunUpfrontSearch(prompt))
    }

    // MARK: - search_documents gating

    private func documentIndex() -> DocumentSearchIndex {
        let document = LibraryDocument(fileName: "notes.txt", kind: .text, indexState: .ready)
        return DocumentSearchIndex(entries: [
            DocumentSearchIndex.Entry(
                document: document,
                chunks: [DocumentChunk(index: 0, text: "vacation policy")],
                vectors: nil
            )
        ])
    }

    func test_searchDocumentsPresentWhenEnabledAndLibraryHasDocuments() {
        let ctx = ToolContext(
            settings: .default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil,
            documentSearchIndex: documentIndex()
        )

        XCTAssertNotNil(ToolRegistry.availableTools(context: ctx).first { $0.name == "search_documents" })
    }

    func test_searchDocumentsAbsentWhenFeatureDisabled() {
        var settings = AppSettings.default
        settings.documentSearchEnabled = false
        let ctx = ToolContext(
            settings: settings,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil,
            documentSearchIndex: documentIndex()
        )

        XCTAssertNil(ToolRegistry.availableTools(context: ctx).first { $0.name == "search_documents" })
    }

    func test_searchDocumentsAbsentWhenLibraryEmpty() {
        let ctx = ToolContext(
            settings: .default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil,
            documentSearchIndex: .empty
        )

        XCTAssertNil(ToolRegistry.availableTools(context: ctx).first { $0.name == "search_documents" })
    }

    func test_documentIntentIsHandledLocally() {
        XCTAssertTrue(UpfrontToolDetector.canHandleLocally(prompt: "What does my document say about vacation?"))
        XCTAssertTrue(UpfrontToolDetector.canHandleLocally(prompt: "Summarize the PDF I attached"))
    }

    // MARK: - Social-prompt gate (tools must not fire on "hi")

    func test_socialPromptsAreDetected() {
        for prompt in ["hi", "Hi!", "hello", "hey there", "Hello!", "thanks",
                       "thank you", "good morning", "how are you?", "what can you do",
                       "ok", "cool", "test",
                       // Greeting + filler variants the exact-match list used to miss.
                       "Hi there!", "hello everyone", "hey you", "hello edge mind",
                       "hey buddy", "yo team"] {
            XCTAssertTrue(UpfrontToolDetector.isSocialOnly(prompt: prompt),
                          "\"\(prompt)\" should be treated as social-only")
        }
    }

    /// A greeting followed by a real request must keep its tools — the filler rule
    /// only applies when the entire remainder is filler.
    func test_greetingFollowedByRequestIsNotSocial() {
        for prompt in ["hey can you help me write a poem", "hi can you search the web",
                       "hello please summarize my document"] {
            XCTAssertFalse(UpfrontToolDetector.isSocialOnly(prompt: prompt),
                           "\"\(prompt)\" is a request and must keep its tools")
        }
    }

    // MARK: - dispatch honours the per-turn tool gate

    func test_dispatchRefusesToolThatWasNotOffered() async {
        var settings = AppSettings.default
        settings.documentSearchEnabled = false
        let ctx = ToolContext(
            settings: settings,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil,
            documentSearchIndex: .empty
        )

        let result = await ToolRegistry.dispatch(
            name: "search_documents",
            argsJSON: #"{"query":"x"}"#,
            context: ctx
        )

        XCTAssertNotNil(result, "a known-but-gated tool should report an error, not vanish")
        XCTAssertTrue(result?.output.contains("not available") == true,
                      "a gated tool must not run; got \(result?.output ?? "nil")")
    }

    func test_dispatchStillRunsOfferedTools() async {
        let ctx = ToolContext(
            settings: .default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )

        let result = await ToolRegistry.dispatch(
            name: "calculate",
            argsJSON: #"{"expression":"6*7"}"#,
            context: ctx
        )

        XCTAssertEqual(result?.output, "Result: 42")
    }

    func test_realRequestsAreNotSocial() {
        for prompt in ["What is 47 * 89?", "what time is it",
                       "What does my document say about vacation?",
                       "Summarize the PDF I attached", "who won the game last night",
                       "Write me a poem about the ocean",
                       "explain quantum tunnelling in detail"] {
            XCTAssertFalse(UpfrontToolDetector.isSocialOnly(prompt: prompt),
                           "\"\(prompt)\" carries real intent and must keep its tools")
        }
    }

    /// A greeting that also asks a real question must NOT be suppressed.
    func test_greetingWithQuestionKeepsTools() {
        XCTAssertFalse(UpfrontToolDetector.isSocialOnly(prompt: "hi, what time is it?"))
        XCTAssertFalse(UpfrontToolDetector.isSocialOnly(prompt: "hello, calculate 12 * 12"))
    }

    /// The rendered section must actively tell the model not to use tools for small talk.
    func test_promptSectionForbidsGreetingToolCalls() {
        let section = ToolRegistry.renderPromptSection(for: ToolRegistry.allTools)
        XCTAssertTrue(section.contains("Do NOT call a tool for greetings"),
                      "the tool section must explicitly forbid greeting tool calls")
    }

    /// Each runtime must be taught the tool-call shape its own model was trained on.
    /// The section used to hardcode the XML form for everyone, so Gemma 4 and LFM2.5
    /// were asked for syntax that is not their native convention.
    func test_promptSectionTeachesEachModelsOwnToolSyntax() {
        let tools = [CalculateTool()]

        let xml = ToolRegistry.renderPromptSection(for: tools, format: .xmlToolCall)
        XCTAssertTrue(xml.contains("<tool_call>"))
        XCTAssertTrue(xml.contains("</tool_call>"))

        let gemma = ToolRegistry.renderPromptSection(for: tools, format: .gemmaNativeToolCall)
        XCTAssertTrue(gemma.contains("call:tool_name"), "Gemma must be shown the call:NAME{…} form")
        XCTAssertTrue(gemma.contains("<|tool_call>"))
        XCTAssertTrue(gemma.contains("<tool_call|>"))

        let liquid = ToolRegistry.renderPromptSection(for: tools, format: .liquidToolCall)
        XCTAssertTrue(liquid.contains("<|tool_call_start|>"))
        XCTAssertTrue(liquid.contains("<|tool_call_end|>"))
    }

    /// Default rendering stays the XML form, so existing callers are unaffected.
    func test_promptSectionDefaultsToXMLFormat() {
        let tools = [CalculateTool()]
        XCTAssertEqual(
            ToolRegistry.renderPromptSection(for: tools),
            ToolRegistry.renderPromptSection(for: tools, format: .xmlToolCall)
        )
    }
}
