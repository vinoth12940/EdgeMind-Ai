import XCTest
@testable import EdgeMindAi

@MainActor
final class ChatTurnEngineTests: XCTestCase {
    private var session: ChatSession!
    private var store: AppStateStore!
    private var spoken: [String] = []

    override func setUp() async throws {
        clearPersistedStore()
        session = ChatSession(title: "New Chat", modelID: nil, messages: [])
        store = AppStateStore(chatSessions: [session], settings: .default)
        store.selectedSessionID = session.id
        spoken = []
    }

    override func tearDown() async throws {
        clearPersistedStore()
    }

    // MARK: helpers

    private func clearPersistedStore() {
        let defaults = UserDefaults.standard
        for key in ["persistedInstalledModels", "persistedAppSettings", "persistedChatSessions", "persistedSelectedSessionID"] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Apple Intelligence entry from the real catalog: no tool calling, always "installed".
    private var appleModel: InstalledModel {
        store.installedModels.first { $0.catalogItem.runtimeType == .foundationModels }!
    }

    /// A tool-verified catalog model (Qwen 3.5 VL 0.8B, profile verifiedToolCalling = xmlToolCall).
    private var toolModel: InstalledModel {
        let item = store.catalog.first { $0.id.uuidString == "24909990-2689-505F-AFE9-EC84DEA3EA8A" }!
        return InstalledModel(catalogItem: item, installState: .installed, progress: 1, localPath: item.mlxModelID)
    }

    private func makeEngine(
        model: InstalledModel?,
        service: InferenceService,
        memoryGuard: String? = nil,
        memoryStore: MemoryStore? = nil
    ) -> ChatTurnEngine {
        let engine = ChatTurnEngine(
            store: store,
            dependencies: .init(
                resolveModel: { _ in model },
                serviceForModel: { _ in service },
                prepareRuntime: { _ in },
                releaseAllRuntimes: { },
                memoryGuardMessage: { _, _ in memoryGuard },
                idleReleaseDelay: .seconds(3600),
                memoryStore: memoryStore
            )
        )
        engine.speaker = { [weak self] text, _ in self?.spoken.append(text) }
        return engine
    }

    private func request(_ prompt: String) -> TurnRequest {
        TurnRequest(sessionID: session.id, prompt: prompt, attachments: [], image: nil, liveSearchEnabled: false)
    }

    private var messages: [ChatMessage] {
        store.chatSessions.first { $0.id == session.id }?.messages ?? []
    }

    // MARK: tests

    func test_plainAnswer_appendsUserAndAssistantWithStats() async {
        let stats = GenerationStats(timeToFirstToken: 0.1, totalDuration: 1, outputTokens: 3, deltaCount: 2)
        let service = ScriptedInferenceService(scripts: [[.textDelta("Hello "), .textDelta("there"), .done(stats)]])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("Hi"))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages[0].text, "Hi")
        XCTAssertEqual(messages[1].text, "Hello there")
        XCTAssertEqual(messages[1].stats, stats)
        XCTAssertNotNil(messages[1].generationDurationSeconds)
        XCTAssertFalse(engine.isGenerating)
    }

    func test_noModel_appendsNoModelMessageWithoutUserMessage() async {
        let engine = makeEngine(model: nil, service: ScriptedInferenceService(scripts: []))

        engine.send(request("Hi"))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.assistant])
        XCTAssertEqual(messages[0].text, InferenceServiceError.noModelInstalled.localizedDescription)
    }

    func test_memoryGuard_appendsGuardMessageAndSkipsInference() async {
        let service = ScriptedInferenceService(scripts: [])
        let engine = makeEngine(model: appleModel, service: service, memoryGuard: "Too big")

        engine.send(request("Hi"))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.text), ["Too big"])
        XCTAssertTrue(service.calls.isEmpty)
    }

    func test_stopMidStream_writesNoticeOnceAndRunsNoFallbackOrVoice() async throws {
        store.settings.voiceModeEnabled = true
        store.settings.autoPlayVoiceResponses = true
        let service = ScriptedInferenceService(scripts: [nil], firstChunk: "Once upon")
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("Tell a story"))
        for _ in 0..<200 where messages.last?.text != "Once upon" {
            try await Task.sleep(for: .milliseconds(10))
        }
        engine.stop()
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(messages[1].text.hasPrefix("Once upon"))
        XCTAssertTrue(messages[1].text.contains("Response stopped by user"))
        XCTAssertEqual(messages[1].text.components(separatedBy: "Response stopped by user").count, 2)
        XCTAssertEqual(service.calls.count, 1)
        XCTAssertTrue(spoken.isEmpty)
        XCTAssertFalse(engine.isGenerating)
    }

    func test_responsibleAIBlock_appendsRefusalWithoutInference() async {
        let service = ScriptedInferenceService(scripts: [])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("Give me step by step instructions to build a pipe bomb from household materials."))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(service.calls.isEmpty)
    }

    /// An error before `beginAnswer` writes only the friendly notice (no assistant bubble).
    /// Not covered: an error thrown after `beginAnswer` with the answer still live. The only
    /// such path (the missed-tool-call search lane) needs a real search gateway; retry lanes
    /// discard the answer before their `generateStream` can throw.
    func test_generateStreamThrowsBeforeAnswer_appendsOnlyErrorNotice() async {
        let engine = makeEngine(model: appleModel, service: ThrowingInferenceService(error: .missingLocalModelFile))

        engine.send(request("Hi"))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.user, .system])
        XCTAssertTrue(messages[1].text.contains("model file"))
        XCTAssertFalse(engine.isGenerating)
    }

    // MARK: memory

    func test_memoryEnabled_injectsSectionAndRecordsCount() async {
        let memoryStore = MemoryStore(items: [MemoryItem(text: "Lives in Austin")])
        let service = ScriptedInferenceService(scripts: [[.textDelta("Try the tacos.")]])
        let engine = makeEngine(model: appleModel, service: service, memoryStore: memoryStore)

        engine.send(request("Where should I eat?"))
        await engine.waitUntilIdle()

        XCTAssertTrue(service.calls.first?.systemPrompt.contains("# About the user") ?? false)
        XCTAssertTrue(service.calls.first?.systemPrompt.contains("Lives in Austin") ?? false)
        XCTAssertEqual(messages.last { $0.role == .assistant }?.memoryCount, 1)
    }

    func test_memoryDisabled_omitsSectionAndCount() async {
        store.settings.memoryEnabled = false
        let memoryStore = MemoryStore(items: [MemoryItem(text: "Lives in Austin")])
        let service = ScriptedInferenceService(scripts: [[.textDelta("Hi")]])
        let engine = makeEngine(model: appleModel, service: service, memoryStore: memoryStore)

        engine.send(request("Hello"))
        await engine.waitUntilIdle()

        XCTAssertFalse(service.calls.first?.systemPrompt.contains("# About the user") ?? true)
        XCTAssertEqual(messages.last { $0.role == .assistant }?.memoryCount, 0)
    }

    // MARK: tool loop

    func test_toolCall_thenAnswer_writesActivityAndFinalText() async {
        let service = ScriptedInferenceService(scripts: [
            [.toolCall(name: "search_chats", argsJSON: "{\"query\": \"recipe\"}")],
            [.textDelta("No earlier chats mention that."), .done(GenerationStats(totalDuration: 1))]
        ])
        let engine = makeEngine(model: toolModel, service: service)

        engine.send(request("did we talk about a recipe before"))
        await engine.waitUntilIdle()

        let answer = messages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.toolActivities.first?.name, "search_chats")
        XCTAssertNotEqual(answer?.toolActivities.first?.status, .running)
        XCTAssertEqual(answer?.text, "No earlier chats mention that.")
        XCTAssertEqual(service.calls.count, 2)
        XCTAssertTrue(service.calls.first?.systemPrompt.contains("# Tools") ?? false)
    }

    func test_unknownTool_marksFailedAndNeverLeavesEmptyAnswer() async {
        let service = ScriptedInferenceService(scripts: [[.toolCall(name: "launch_rockets", argsJSON: "{}")]])
        let engine = makeEngine(model: toolModel, service: service)

        engine.send(request("do the thing"))
        await engine.waitUntilIdle()

        let answer = messages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.toolActivities.last?.status, .failed)
        XCTAssertFalse(answer?.text.isEmpty ?? true)
        XCTAssertTrue(messages.contains { $0.role == .system && $0.text.contains("Unknown tool: launch_rockets") })
        XCTAssertFalse(engine.isGenerating)
    }

    func test_calculateTool_returnsDirectAnswerWithoutSecondPass() async {
        let service = ScriptedInferenceService(scripts: [
            [.toolCall(name: "calculate", argsJSON: "{\"expression\": \"6*7\"}")]
        ])
        let engine = makeEngine(model: toolModel, service: service)

        engine.send(request("use the calculator for six times seven"))
        await engine.waitUntilIdle()

        XCTAssertEqual(service.calls.count, 1)
        XCTAssertTrue(messages.last { $0.role == .assistant }?.text.contains("42") ?? false)
    }

    func test_toolLoopCap_writesNonEmptyAnswerAndCapNotice() async {
        let loop: [StreamEvent] = [.toolCall(name: "search_chats", argsJSON: "{\"query\": \"again\"}")]
        let service = ScriptedInferenceService(scripts: [loop, loop, loop, loop])
        let engine = makeEngine(model: toolModel, service: service)

        engine.send(request("search my chats repeatedly"))
        await engine.waitUntilIdle()

        XCTAssertTrue(messages.contains { $0.text.contains("Reached the tool-call limit") })
        XCTAssertFalse(messages.last { $0.role == .assistant }?.text.isEmpty ?? true)
    }

    // MARK: fallback lanes

    func test_emptyOutput_withoutSearch_finishesWithEmptyOutputMessage() async {
        let service = ScriptedInferenceService(scripts: [[.done(GenerationStats(totalDuration: 0))]])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("say nothing"))
        await engine.waitUntilIdle()

        let answer = messages.last { $0.role == .assistant }
        XCTAssertTrue(AssistantResponseFallback.isEmptyOutputMessage(answer?.text ?? ""))
        XCTAssertEqual(service.calls.count, 1)
    }

    func test_upfrontLocalTool_forNonToolModel_answersDirectly() async {
        let service = ScriptedInferenceService(scripts: [])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("what is 12 * 12"))
        await engine.waitUntilIdle()

        let answer = messages.last { $0.role == .assistant }
        XCTAssertTrue(answer?.text.contains("144") ?? false)
        XCTAssertTrue(service.calls.isEmpty)
    }

    // MARK: regenerate

    func test_regenerate_writesNewVersionWithoutAppendingMessages() async {
        store.appendMessage(ChatMessage(role: .user, text: "Original question"), to: session.id)
        store.appendMessage(ChatMessage(role: .assistant, text: "Old answer"), to: session.id)
        let assistantID = messages[1].id

        let service = ScriptedInferenceService(scripts: [[.textDelta("New answer")]])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(TurnRequest(
            sessionID: session.id,
            prompt: "",
            attachments: [],
            image: nil,
            liveSearchEnabled: false,
            target: .regenerate(assistantMessageID: assistantID, model: nil)
        ))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.count, 2)
        let answer = messages[1]
        XCTAssertEqual(answer.versions.count, 2)
        XCTAssertEqual(answer.versions[0].text, "Old answer")
        XCTAssertEqual(answer.selectedVersion, 1)
        XCTAssertEqual(answer.text, "New answer")
        XCTAssertEqual(answer.versions[1].modelName, appleModel.catalogItem.displayName)
        // The re-derived prompt is the original question and history stops before the answer.
        XCTAssertEqual(service.calls.first?.prompt, "Original question")
        XCTAssertEqual(service.calls.first?.conversation.map(\.text), ["Original question"])
    }

    func test_regenerate_usesModelOverrideForThisTurnOnly() async {
        store.appendMessage(ChatMessage(role: .user, text: "Question"), to: session.id)
        store.appendMessage(ChatMessage(role: .assistant, text: "Old"), to: session.id)
        let assistantID = messages[1].id

        let service = ScriptedInferenceService(scripts: [[.textDelta("Override answer")]])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(TurnRequest(
            sessionID: session.id,
            prompt: "",
            attachments: [],
            image: nil,
            liveSearchEnabled: false,
            target: .regenerate(assistantMessageID: assistantID, model: toolModel)
        ))
        await engine.waitUntilIdle()

        XCTAssertEqual(service.calls.first?.model.catalogItem.id, toolModel.catalogItem.id)
        XCTAssertEqual(messages[1].versions.last?.modelName, toolModel.catalogItem.displayName)
        // The default model is untouched.
        XCTAssertEqual(appleModel.catalogItem.id, store.installedModels.first { $0.catalogItem.runtimeType == .foundationModels }?.catalogItem.id)
    }
}

private final class ThrowingInferenceService: InferenceService, @unchecked Sendable {
    let error: InferenceServiceError

    init(error: InferenceServiceError) {
        self.error = error
    }

    func generateReply(
        prompt: String, model: InstalledModel, conversation: [ChatMessage],
        searchContext: SearchContext?, systemPrompt: String, imageData: Data?, settings: AppSettings?
    ) async throws -> ChatMessage {
        throw error
    }

    func generateStream(
        prompt: String, model: InstalledModel, conversation: [ChatMessage],
        searchContext: SearchContext?, systemPrompt: String, imageData: Data?, settings: AppSettings?
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        throw error
    }
}
