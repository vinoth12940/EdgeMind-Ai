// EdgeMindAiTests/AppStateStoreMigrationTests.swift
import XCTest
@testable import EdgeMindAi

final class AppStateStoreMigrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearPersistedStore()
    }

    override func tearDown() {
        clearPersistedStore()
        super.tearDown()
    }

    @MainActor
    func test_freshStoreSeedsAppleSystemModelAsDefault() {
        let store = AppStateStore(chatSessions: [], settings: .default)

        XCTAssertEqual(store.defaultModel?.catalogItem.runtimeType, .foundationModels)
        XCTAssertEqual(store.defaultModel?.localPath, AppleFoundationModelService.localPathMarker)
        XCTAssertEqual(store.settings.defaultModelID, store.defaultModel?.catalogItem.id)
    }

    @MainActor
    func test_deleteSessionSelectsNextConversation() {
        let first = ChatSession(title: "First", modelID: nil, messages: [])
        let second = ChatSession(title: "Second", modelID: nil, messages: [])
        let store = AppStateStore(catalog: [], installedModels: [], chatSessions: [first, second], settings: .default)

        store.selectedSessionID = first.id
        store.deleteSession(first.id)

        XCTAssertEqual(store.chatSessions.map(\.id), [second.id])
        XCTAssertEqual(store.selectedSessionID, second.id)
    }

    @MainActor
    func test_deleteAllSessionsClearsSelection() {
        let first = ChatSession(title: "First", modelID: nil, messages: [])
        let second = ChatSession(title: "Second", modelID: nil, messages: [])
        let store = AppStateStore(catalog: [], installedModels: [], chatSessions: [first, second], settings: .default)

        store.selectedSessionID = second.id
        store.deleteAllSessions()

        XCTAssertTrue(store.chatSessions.isEmpty)
        XCTAssertNil(store.selectedSessionID)
        XCTAssertNil(store.selectedSession)
    }

    @MainActor
    func test_initRemovesDeprecatedOpenELMAndKeepsSupportedModels() {
        let openELM = deprecatedItem(
            name: "OpenELM 1.1B Instruct (MLX)",
            family: .openELM,
            modelID: "mlx-community/OpenELM-1_1B-Instruct-4bit"
        )
        let lfm = deprecatedItem(
            name: "LFM2.5 1.2B Instruct (MLX)",
            family: .lfm,
            modelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit"
        )
        let qwen = deprecatedItem(
            name: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            modelID: "mlx-community/Qwen3-0.6B-4bit"
        )
        var settings = AppSettings.default
        settings.defaultModelID = openELM.id

        let store = AppStateStore(
            catalog: [lfm, qwen],
            installedModels: [
                InstalledModel(catalogItem: openELM, installState: .installed, progress: 1, isDefault: true),
                InstalledModel(catalogItem: lfm, installState: .installed, progress: 1),
                InstalledModel(catalogItem: qwen, installState: .installed, progress: 1)
            ],
            chatSessions: [],
            settings: settings
        )

        XCTAssertEqual(store.installedModels.map(\.catalogItem.mlxModelID), [lfm.mlxModelID, qwen.mlxModelID])
        XCTAssertNil(store.settings.defaultModelID)
    }

    @MainActor
    func test_initNormalizesPersistedMLXPathForCurrentCatalogItem() {
        let qwen = deprecatedItem(
            name: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            modelID: "mlx-community/Qwen3-0.6B-4bit"
        )

        let store = AppStateStore(
            catalog: [qwen],
            installedModels: [
                InstalledModel(catalogItem: qwen, installState: .installed, progress: 1, localPath: nil)
            ],
            chatSessions: [],
            settings: .default
        )

        XCTAssertEqual(store.installedModels.first?.localPath, qwen.mlxModelID)
    }

    @MainActor
    func test_initRemovesDeprecatedGemmaMLXInstalls() {
        let gemma3n = deprecatedItem(
            name: "Gemma 3n E2B Instruct (MLX)",
            family: .gemma,
            modelID: "mlx-community/gemma-3n-E2B-it-4bit"
        )
        let gemma34B = deprecatedItem(
            name: "Gemma 3 4B Instruct (MLX)",
            family: .gemma,
            modelID: "mlx-community/gemma-3-4b-it-4bit"
        )
        let qwen = deprecatedItem(
            name: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            modelID: "mlx-community/Qwen3-0.6B-4bit"
        )
        var settings = AppSettings.default
        settings.defaultModelID = gemma3n.id

        let store = AppStateStore(
            catalog: [qwen],
            installedModels: [
                InstalledModel(catalogItem: gemma3n, installState: .installed, progress: 1, localPath: gemma3n.mlxModelID, isDefault: true),
                InstalledModel(catalogItem: gemma34B, installState: .installed, progress: 1, localPath: gemma34B.mlxModelID),
                InstalledModel(catalogItem: qwen, installState: .installed, progress: 1, localPath: qwen.mlxModelID)
            ],
            chatSessions: [],
            settings: settings
        )

        XCTAssertEqual(store.installedModels.map(\.catalogItem.mlxModelID), [qwen.mlxModelID])
        XCTAssertNil(store.settings.defaultModelID)
    }

    @MainActor
    func test_initRemovesDeprecatedGemmaLiteRTTaskInstalls() {
        let staleLiteRT = liteRTItem(
            name: "Gemma 3 270M LiteRT-LM",
            fileName: "gemma3-270m-it-q8.task"
        )
        var settings = AppSettings.default
        settings.defaultModelID = staleLiteRT.id

        let store = AppStateStore(
            catalog: [],
            installedModels: [
                InstalledModel(
                    catalogItem: staleLiteRT,
                    installState: .installed,
                    progress: 1,
                    localPath: "/tmp/gemma3-270m-it-q8.task",
                    isDefault: true
                )
            ],
            chatSessions: [],
            settings: settings
        )

        XCTAssertFalse(store.installedModels.contains { $0.catalogItem.id == staleLiteRT.id })
        XCTAssertNil(store.settings.defaultModelID)
    }

    @MainActor
    func test_setDefaultModelAcceptsInstalledMLXModelOnDeviceBuilds() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX chat models are intentionally hidden in simulator builds.")
        #else
        let qwen = deprecatedItem(
            name: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            modelID: "mlx-community/Qwen3-0.6B-4bit"
        )
        let store = AppStateStore(
            catalog: [qwen],
            installedModels: [
                InstalledModel(catalogItem: qwen, installState: .installed, progress: 1, localPath: qwen.mlxModelID)
            ],
            chatSessions: [],
            settings: .default
        )

        store.setDefaultModel(id: qwen.id)

        XCTAssertEqual(store.defaultModel?.catalogItem.id, qwen.id)
        XCTAssertEqual(store.settings.defaultModelID, qwen.id)
        #endif
    }

    @MainActor
    func test_initBoundsPersistedLongConversationButKeepsTitleSeedAndRecentTurns() throws {
        let firstUser = ChatMessage(
            role: .user,
            text: "Keep this title seed",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let tailMessages = (1...240).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? .assistant : .user,
                text: "turn \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index + 1))
            )
        }
        let session = ChatSession(
            title: "New Chat",
            modelID: nil,
            messages: [firstUser] + tailMessages,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 500)
        )
        try persistChatSessions([session])

        let store = AppStateStore(catalog: [], installedModels: [], chatSessions: [], settings: .default)
        let loaded = try XCTUnwrap(store.chatSessions.first)

        XCTAssertEqual(loaded.messages.count, 180)
        XCTAssertEqual(loaded.messages.first?.id, firstUser.id)
        XCTAssertEqual(loaded.messages.last?.text, "turn 240")
        XCTAssertEqual(loaded.title, "Keep this title seed")
    }

    @MainActor
    func test_initBoundsPersistedSessionCountToNewestSessions() throws {
        let sessions = (1...45).map { index in
            ChatSession(
                title: "Session \(index)",
                modelID: nil,
                messages: [ChatMessage(role: .user, text: "prompt \(index)")],
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        try persistChatSessions(sessions)

        let store = AppStateStore(catalog: [], installedModels: [], chatSessions: [], settings: .default)

        XCTAssertEqual(store.chatSessions.count, 40)
        XCTAssertEqual(store.chatSessions.first?.title, "Session 45")
        XCTAssertFalse(store.chatSessions.contains(where: { $0.title == "Session 1" }))
    }

    @MainActor
    func test_appendMessageBoundsInMemoryConversation() {
        let firstUser = ChatMessage(role: .user, text: "first user prompt")
        let session = ChatSession(title: "New Chat", modelID: nil, messages: [firstUser])
        let store = AppStateStore(catalog: [], installedModels: [], chatSessions: [session], settings: .default)

        for index in 1...300 {
            store.appendMessage(
                ChatMessage(
                    role: index.isMultiple(of: 2) ? .assistant : .user,
                    text: "turn \(index)"
                ),
                to: session.id
            )
        }

        let loaded = store.chatSessions.first
        XCTAssertEqual(loaded?.messages.count, 260)
        XCTAssertEqual(loaded?.messages.first?.id, firstUser.id)
        XCTAssertEqual(loaded?.messages.last?.text, "turn 300")
    }

    @MainActor
    func test_updateMessageTextCapsLiveAssistantText() {
        let message = ChatMessage(role: .assistant, text: "")
        let session = ChatSession(title: "New Chat", modelID: nil, messages: [message])
        let store = AppStateStore(catalog: [], installedModels: [], chatSessions: [session], settings: .default)
        let oversized = String(repeating: "A", count: 140_000) + "tail"

        store.updateMessageText(message.id, in: session.id, text: oversized, persist: false)

        let text = store.chatSessions.first?.messages.first?.text ?? ""
        XCTAssertLessThan(text.count, oversized.count)
        XCTAssertLessThanOrEqual(text.count, 96_000)
        XCTAssertTrue(text.contains("trimmed for on-device memory safety"))
        XCTAssertTrue(text.hasSuffix("tail"))
    }

    @MainActor
    func test_updateMessageThinkingCapsLiveThinkingText() {
        let message = ChatMessage(role: .assistant, text: "")
        let session = ChatSession(title: "New Chat", modelID: nil, messages: [message])
        let store = AppStateStore(catalog: [], installedModels: [], chatSessions: [session], settings: .default)
        let oversized = String(repeating: "R", count: 90_000) + "done"

        store.updateMessageThinking(message.id, in: session.id, thinkingContent: oversized)

        let thinking = store.chatSessions.first?.messages.first?.thinkingContent ?? ""
        XCTAssertLessThan(thinking.count, oversized.count)
        XCTAssertLessThanOrEqual(thinking.count, 64_000)
        XCTAssertTrue(thinking.contains("trimmed for on-device memory safety"))
        XCTAssertTrue(thinking.hasSuffix("done"))
    }

    @MainActor
    func test_initBoundsInjectedLongConversation() {
        let firstUser = ChatMessage(role: .user, text: "first")
        let session = ChatSession(
            title: "New Chat",
            modelID: nil,
            messages: [firstUser] + (1...280).map { ChatMessage(role: .assistant, text: "turn \($0)") }
        )

        let store = AppStateStore(catalog: [], installedModels: [], chatSessions: [session], settings: .default)
        let loaded = store.chatSessions.first

        XCTAssertEqual(loaded?.messages.count, 260)
        XCTAssertEqual(loaded?.messages.first?.id, firstUser.id)
        XCTAssertEqual(loaded?.messages.last?.text, "turn 280")
    }

    func test_legacySearchRoleDecodesAsSystemNotice() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "role": "search",
          "text": "Searching: local models",
          "createdAt": 0,
          "citations": [],
          "attachments": []
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ChatMessage.self, from: json)

        XCTAssertEqual(message.role, .system)
        XCTAssertEqual(message.text, "Searching: local models")
    }

    private func deprecatedItem(
        name: String,
        family: ModelCatalogItem.ModelFamily,
        modelID: String
    ) -> ModelCatalogItem {
        ModelCatalogItem(
            displayName: name,
            family: family,
            variant: "4-bit MLX",
            summary: "",
            parameterSize: "1B",
            quantization: "MLX 4-bit",
            diskSize: "~1 GB",
            contextWindow: "2K",
            runtimeType: .mlx,
            mlxModelID: modelID,
            minimumTier: .standard
        )
    }

    private func liteRTItem(name: String, fileName: String) -> ModelCatalogItem {
        ModelCatalogItem(
            displayName: name,
            family: .gemma,
            variant: "LiteRT-LM",
            summary: "",
            parameterSize: "1B",
            quantization: "LiteRT",
            diskSize: "~1 GB",
            contextWindow: "2K",
            downloadURL: URL(string: "https://example.com/\(fileName)")!,
            runtimeType: .liteRTLM,
            minimumTier: .standard
        )
    }

    private func persistChatSessions(_ sessions: [ChatSession]) throws {
        let data = try JSONEncoder().encode(sessions)
        UserDefaults.standard.set(data, forKey: "persistedChatSessions")
    }

    private func clearPersistedStore() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "persistedInstalledModels")
        defaults.removeObject(forKey: "persistedAppSettings")
        defaults.removeObject(forKey: "persistedChatSessions")
        defaults.removeObject(forKey: "persistedSelectedSessionID")
    }
}
