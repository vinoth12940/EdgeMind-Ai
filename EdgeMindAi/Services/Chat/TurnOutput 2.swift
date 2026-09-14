import Foundation
import OSLog

/// Every write a chat turn makes. `StoreTurnOutput` maps each call 1:1 onto the
/// `AppStateStore` mutations `ChatView` used before step 0; later steps add
/// version-aware and headless outputs.
@MainActor
protocol TurnOutput: AnyObject {
    /// Appends the assistant placeholder that streaming updates target.
    func beginAnswer(messageID: UUID, citations: [SearchCitation])
    /// Removes the current answer message; later writes are ignored until the
    /// next `beginAnswer` (retry lanes discard the stale answer before retrying).
    func discardAnswer()
    func update(text: String, persist: Bool)
    func update(thinking: String, duration: Int?, persist: Bool)
    func setToolActivities(_ activities: [ChatToolActivity], persist: Bool)
    func setCitations(_ citations: [SearchCitation])
    /// Appends a system notice (warnings, retry banners).
    func appendNotice(_ text: String)
    /// Terminal write. If no answer was begun, appends a new assistant message.
    /// Calls after the first are ignored.
    func finish(text: String, toolActivities: [ChatToolActivity]?, stats: GenerationStats?, duration: Double?)
    /// Terminal write for turns that end with no answer message (errors before
    /// `beginAnswer` or after `discardAnswer`): marks the turn finished, writes nothing.
    func finishWithoutAnswer()
    /// True while an answer message is begun and not discarded.
    var hasActiveAnswer: Bool { get }
    var isFinished: Bool { get }
}

@MainActor
final class StoreTurnOutput: TurnOutput {
    private let store: AppStateStore
    private let sessionID: UUID
    private(set) var answerMessageID: UUID?
    private(set) var isFinished = false
    private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "TurnOutput")

    init(store: AppStateStore, sessionID: UUID) {
        self.store = store
        self.sessionID = sessionID
    }

    func beginAnswer(messageID: UUID, citations: [SearchCitation]) {
        answerMessageID = messageID
        store.appendMessage(ChatMessage(id: messageID, role: .assistant, text: "", citations: citations), to: sessionID)
    }

    var hasActiveAnswer: Bool { answerMessageID != nil }

    func discardAnswer() {
        guard let answerMessageID else { return }
        store.removeMessage(answerMessageID, from: sessionID)
        self.answerMessageID = nil
    }

    func update(text: String, persist: Bool) {
        guard let answerMessageID else { return }
        store.updateMessageText(answerMessageID, in: sessionID, text: text, persist: persist)
    }

    func update(thinking: String, duration: Int?, persist: Bool) {
        guard let answerMessageID else { return }
        store.updateMessageThinking(answerMessageID, in: sessionID, thinkingContent: thinking, thinkingDurationSeconds: duration, persist: persist)
    }

    func setToolActivities(_ activities: [ChatToolActivity], persist: Bool) {
        guard let answerMessageID else { return }
        store.updateMessageToolActivities(answerMessageID, in: sessionID, toolActivities: activities, persist: persist)
    }

    func setCitations(_ citations: [SearchCitation]) {
        guard let answerMessageID else { return }
        store.updateMessageCitations(answerMessageID, in: sessionID, citations: citations, persist: true)
    }

    func appendNotice(_ text: String) {
        store.appendMessage(ChatMessage(role: .system, text: text), to: sessionID)
    }

    func finish(text: String, toolActivities: [ChatToolActivity]?, stats: GenerationStats?, duration: Double?) {
        guard !isFinished else {
            logger.error("finish called twice; ignoring second call")
            return
        }
        isFinished = true
        guard let answerMessageID else {
            store.appendMessage(
                ChatMessage(role: .assistant, text: text, toolActivities: toolActivities ?? []),
                to: sessionID
            )
            return
        }
        if let duration {
            store.updateMessageGenerationDuration(answerMessageID, in: sessionID, duration: duration, persist: true)
        }
        store.updateMessageStats(answerMessageID, in: sessionID, stats: stats, persist: true)
        store.updateMessageText(answerMessageID, in: sessionID, text: text, persist: true)
    }

    func finishWithoutAnswer() {
        guard !isFinished else {
            logger.error("finishWithoutAnswer called after finish; ignoring")
            return
        }
        isFinished = true
    }
}
