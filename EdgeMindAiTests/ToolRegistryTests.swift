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
}
