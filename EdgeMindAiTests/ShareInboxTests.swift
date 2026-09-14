import XCTest
@testable import EdgeMindAi

@MainActor
final class ShareInboxTests: XCTestCase {
    private var root: URL!
    private var inbox: ShareInbox!
    private var library: DocumentLibraryStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxTests-\(UUID().uuidString)", isDirectory: true)
        inbox = ShareInbox(inboxURL: root.appendingPathComponent("Inbox", isDirectory: true))
        library = DocumentLibraryStore(directory: root.appendingPathComponent("Library", isDirectory: true))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Round trip

    func test_payloadRoundTrip() throws {
        let payload = SharePayload(action: .ask, question: "What is this?", text: "shared body")

        try inbox.enqueue(payload)

        let pending = inbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, payload.id)
        XCTAssertEqual(pending.first?.action, .ask)
        XCTAssertEqual(pending.first?.question, "What is this?")
        XCTAssertEqual(inbox.payload(id: payload.id)?.text, "shared body")
    }

    func test_pendingIsOldestFirst() throws {
        let older = SharePayload(action: .summarize, text: "older", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = SharePayload(action: .summarize, text: "newer", createdAt: Date(timeIntervalSince1970: 2_000))
        try inbox.enqueue(newer)
        try inbox.enqueue(older)

        XCTAssertEqual(inbox.pending(now: Date(timeIntervalSince1970: 2_100)).map(\.text), ["older", "newer"])
    }

    func test_copiedFileIsStoredAndReturned() throws {
        let payload = SharePayload(action: .summarize, fileName: "notes.txt")
        try inbox.enqueue(payload, fileContents: Data("hello".utf8))

        let stored = try XCTUnwrap(inbox.fileURL(for: payload))
        XCTAssertEqual(try String(contentsOf: stored, encoding: .utf8), "hello")
    }

    func test_removeDeletesItem() throws {
        let payload = SharePayload(action: .summarize, text: "gone")
        try inbox.enqueue(payload)

        inbox.remove(id: payload.id)

        XCTAssertTrue(inbox.pending().isEmpty)
        XCTAssertNil(inbox.payload(id: payload.id))
    }

    func test_staleItemsArePurged() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fresh = SharePayload(action: .summarize, text: "fresh", createdAt: now.addingTimeInterval(-60))
        let stale = SharePayload(action: .summarize, text: "stale", createdAt: now.addingTimeInterval(-ShareInbox.staleItemAge - 60))
        try inbox.enqueue(fresh)
        try inbox.enqueue(stale)

        let pending = inbox.pending(now: now)

        XCTAssertEqual(pending.map(\.text), ["fresh"])
        XCTAssertNil(inbox.payload(id: stale.id))
    }

    func test_missingContainerThrows() {
        let orphan = ShareInbox(inboxURL: nil)
        XCTAssertThrowsError(try orphan.enqueue(SharePayload(action: .ask, question: "hi")))
        XCTAssertTrue(orphan.pending().isEmpty)
    }

    // MARK: - Processor

    func test_sharedTextBecomesChatAttachmentAndRemovesItem() async {
        let payload = SharePayload(action: .ask, question: "Summarize", text: "Body text")
        try? inbox.enqueue(payload)

        let outcome = await ShareInboxProcessor.process(payload, inbox: inbox, library: library)

        XCTAssertEqual(outcome?.prompt, "Summarize")
        XCTAssertEqual(outcome?.attachments.first?.extractedText, "Body text")
        XCTAssertTrue(inbox.pending().isEmpty)
    }

    func test_sharedTextWithNoQuestionUsesTheTextAsPrompt() async {
        let payload = SharePayload(action: .ask, text: "Explain this to me")
        try? inbox.enqueue(payload)

        let outcome = await ShareInboxProcessor.process(payload, inbox: inbox, library: library)

        XCTAssertEqual(outcome?.prompt, "Explain this to me")
    }

    func test_summarizeUsesTheActionPrompt() async {
        let payload = SharePayload(action: .summarize, text: "Long article body")
        try? inbox.enqueue(payload)

        let outcome = await ShareInboxProcessor.process(payload, inbox: inbox, library: library)

        XCTAssertEqual(outcome?.prompt, ShareAction.summarize.promptPrefix)
    }

    func test_sharedDocumentImportsToLibraryAndAttachesText() async throws {
        let payload = SharePayload(action: .summarize, fileName: "notes.txt")
        try inbox.enqueue(payload, fileContents: Data("Vacation policy is 20 days.".utf8))

        let processed = await ShareInboxProcessor.process(payload, inbox: inbox, library: library)
        let outcome = try XCTUnwrap(processed)

        XCTAssertEqual(outcome.importedDocumentNames, ["notes.txt"])
        XCTAssertEqual(library.documents.count, 1)
        XCTAssertTrue(library.documents[0].isReady)
        XCTAssertEqual(outcome.attachments.first?.kind, .text)
        XCTAssertTrue(outcome.attachments.first?.extractedText?.contains("Vacation policy") ?? false)
    }

    func test_emptyPayloadIsDiscarded() async {
        let payload = SharePayload(action: .summarize)
        try? inbox.enqueue(payload)

        let outcome = await ShareInboxProcessor.process(payload, inbox: inbox, library: library)

        XCTAssertNil(outcome)
        XCTAssertTrue(inbox.pending().isEmpty)
    }

    func test_drainPendingProcessesEveryItem() async {
        try? inbox.enqueue(SharePayload(action: .ask, text: "one", createdAt: Date().addingTimeInterval(-20)))
        try? inbox.enqueue(SharePayload(action: .ask, text: "two", createdAt: Date().addingTimeInterval(-10)))

        let outcomes = await ShareInboxProcessor.drainPending(inbox: inbox, library: library)

        XCTAssertEqual(outcomes.count, 2)
        XCTAssertTrue(inbox.pending().isEmpty)
    }
}
