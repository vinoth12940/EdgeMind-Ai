import XCTest
@testable import EdgeMindAi

@MainActor
final class AnswerVersionTests: XCTestCase {
    private var session: ChatSession!
    private var store: AppStateStore!

    private static let keys = [
        "persistedInstalledModels",
        "persistedAppSettings",
        "persistedChatSessions",
        "persistedSelectedSessionID"
    ]

    override func setUp() async throws {
        Self.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        session = ChatSession(
            title: "Versioned",
            modelID: nil,
            messages: [
                ChatMessage(role: .user, text: "hello"),
                ChatMessage(role: .assistant, text: "first answer", stats: GenerationStats(totalDuration: 1))
            ]
        )
        store = AppStateStore(chatSessions: [session], settings: .default)
        store.selectedSessionID = session.id
    }

    override func tearDown() async throws {
        Self.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private var assistantID: UUID {
        store.chatSessions[0].messages[1].id
    }

    private var assistant: ChatMessage {
        store.chatSessions[0].messages[1]
    }

    func test_firstRegeneration_snapshotsVersionZeroAndSelectsNewVersion() {
        let versionID = store.beginRegeneration(assistantID, in: session.id, modelName: "Model A")

        XCTAssertNotNil(versionID)
        XCTAssertEqual(assistant.versions.count, 2)
        XCTAssertEqual(assistant.versions[0].text, "first answer")
        XCTAssertEqual(assistant.versions[0].stats, GenerationStats(totalDuration: 1))
        XCTAssertEqual(assistant.versions[1].id, versionID)
        XCTAssertEqual(assistant.versions[1].modelName, "Model A")
        XCTAssertEqual(assistant.selectedVersion, 1)
        XCTAssertEqual(assistant.text, "")
    }

    func test_updateMessageText_writesSelectedVersionAndMirror() {
        store.beginRegeneration(assistantID, in: session.id, modelName: "Model A")
        store.updateMessageText(assistantID, in: session.id, text: "second answer")

        XCTAssertEqual(assistant.text, "second answer")
        XCTAssertEqual(assistant.versions[1].text, "second answer")
        XCTAssertEqual(assistant.versions[0].text, "first answer")
    }

    func test_selectVersion_mirrorsFields() {
        store.beginRegeneration(assistantID, in: session.id, modelName: "Model A")
        store.updateMessageText(assistantID, in: session.id, text: "second answer")
        store.selectVersion(0, of: assistantID, in: session.id)

        XCTAssertEqual(assistant.selectedVersion, 0)
        XCTAssertEqual(assistant.text, "first answer")
        XCTAssertEqual(assistant.stats, GenerationStats(totalDuration: 1))

        store.selectVersion(1, of: assistantID, in: session.id)
        XCTAssertEqual(assistant.text, "second answer")
    }

    func test_versionCap_removesOldestNonSelected() {
        for index in 0..<6 {
            store.beginRegeneration(assistantID, in: session.id, modelName: "Model \(index)")
            store.updateMessageText(assistantID, in: session.id, text: "answer \(index)")
        }

        XCTAssertEqual(assistant.versions.count, AppStateStore.maxAnswerVersions)
        XCTAssertEqual(assistant.selectedVersion, AppStateStore.maxAnswerVersions - 1)
        // The original snapshot is the oldest non-selected version and is evicted first.
        XCTAssertFalse(assistant.versions.contains { $0.text == "first answer" })
        // The newest answer is still selected and mirrored.
        XCTAssertEqual(assistant.text, "answer 5")
    }

    func test_removeVersion_fallsBackToRemainingSelection() {
        let versionID = store.beginRegeneration(assistantID, in: session.id, modelName: "Model A")!
        store.updateMessageText(assistantID, in: session.id, text: "second answer")

        store.removeVersion(versionID, from: assistantID, in: session.id)

        XCTAssertEqual(assistant.versions.count, 1)
        XCTAssertEqual(assistant.selectedVersion, 0)
        XCTAssertEqual(assistant.text, "first answer")
    }

    func test_persistenceRoundTrip_keepsVersions() {
        store.beginRegeneration(assistantID, in: session.id, modelName: "Model A")
        store.updateMessageText(assistantID, in: session.id, text: "second answer", persist: true)
        store.selectVersion(0, of: assistantID, in: session.id)

        let reloaded = AppStateStore(chatSessions: [], settings: .default)
        let message = reloaded.chatSessions
            .first { $0.id == session.id }?
            .messages
            .first { $0.id == assistantID }

        XCTAssertEqual(message?.versions.count, 2)
        XCTAssertEqual(message?.versions[1].text, "second answer")
        XCTAssertEqual(message?.versions[1].modelName, "Model A")
        XCTAssertEqual(message?.selectedVersion, 0)
        XCTAssertEqual(message?.text, "first answer")
    }

    func test_legacyDecode_withoutVersionKeys_defaultsToEmpty() throws {
        let legacy = """
        {
          "id": "\(UUID().uuidString)",
          "role": "assistant",
          "text": "old answer",
          "createdAt": 0,
          "citations": [],
          "attachments": [],
          "toolActivities": []
        }
        """
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(legacy.utf8))

        XCTAssertTrue(message.versions.isEmpty)
        XCTAssertEqual(message.selectedVersion, 0)
        XCTAssertEqual(message.text, "old answer")
    }
}
