import XCTest
@testable import EdgeMindAi

@MainActor
final class EditMessageTests: XCTestCase {
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
            title: "Editable",
            modelID: nil,
            messages: [
                ChatMessage(role: .user, text: "first question"),
                ChatMessage(role: .assistant, text: "first answer"),
                ChatMessage(role: .user, text: "second question", attachments: [.image(Data([1, 2, 3]), fileName: "shot.jpg")]),
                ChatMessage(role: .assistant, text: "second answer")
            ]
        )
        store = AppStateStore(chatSessions: [session], settings: .default)
        store.selectedSessionID = session.id
    }

    override func tearDown() async throws {
        Self.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private var messages: [ChatMessage] {
        store.chatSessions.first { $0.id == session.id }?.messages ?? []
    }

    func test_removesEditedUserMessageAndEverythingAfter() {
        let target = messages[2]
        let removed = store.removeMessagesForEdit(from: target.id, in: session.id)

        XCTAssertEqual(removed?.id, target.id)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.map(\.text), ["first question", "first answer"])
    }

    func test_removedMessageKeepsItsAttachments() {
        let target = messages[2]
        let removed = store.removeMessagesForEdit(from: target.id, in: session.id)

        XCTAssertEqual(removed?.attachments.count, 1)
        XCTAssertEqual(removed?.attachments.first?.fileName, "shot.jpg")
        XCTAssertEqual(removed?.attachments.first?.rawData, Data([1, 2, 3]))
    }

    func test_nonUserMessageIsRejectedWithoutChange() {
        let before = messages
        let removed = store.removeMessagesForEdit(from: messages[1].id, in: session.id)

        XCTAssertNil(removed)
        XCTAssertEqual(messages, before)
    }

    func test_unknownMessageIsRejectedWithoutChange() {
        let before = messages
        let removed = store.removeMessagesForEdit(from: UUID(), in: session.id)

        XCTAssertNil(removed)
        XCTAssertEqual(messages, before)
    }
}
