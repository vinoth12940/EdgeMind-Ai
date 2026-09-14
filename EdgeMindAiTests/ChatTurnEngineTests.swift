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
        memoryGuard: String? = nil
    ) -> ChatTurnEngine {
        let engine = ChatTurnEngine(
            store: store,
            dependencies: .init(
                resolveModel: { _ in model },
                serviceForModel: { _ in service },
                prepareRuntime: { _ in },
                releaseAllRuntimes: { },
                memoryGuardMessage: { _, _ in memoryGuard },
                idleReleaseDelay: .seconds(3600)
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
}
