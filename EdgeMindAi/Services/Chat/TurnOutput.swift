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
    /// Records how many saved memories shaped this answer.
    func setMemoryCount(_ count: Int)
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
    /// Which store mutation a turn's writes target.
    enum Mode {
        /// Append a new assistant message (a fresh user turn).
        case newMessage
        /// Write into a new version of an existing assistant message.
        case regenerate(assistantMessageID: UUID, modelName: String)

        var isRegenerate: Bool {
            if case .regenerate = self { return true }
            return false
        }
    }

    private let store: AppStateStore
    private let sessionID: UUID
    private let mode: Mode
    private(set) var answerMessageID: UUID?
    private var activeVersionID: UUID?
    private(set) var isFinished = false
    private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "TurnOutput")

    init(store: AppStateStore, sessionID: UUID, mode: Mode = .newMessage) {
        self.store = store
        self.sessionID = sessionID
        self.mode = mode
    }

    func beginAnswer(messageID: UUID, citations: [SearchCitation]) {
        switch mode {
        case .newMessage:
            answerMessageID = messageID
            store.appendMessage(ChatMessage(id: messageID, role: .assistant, text: "", citations: citations), to: sessionID)
        case .regenerate(let assistantMessageID, let modelName):
            answerMessageID = assistantMessageID
            activeVersionID = store.beginRegeneration(
                assistantMessageID,
                in: sessionID,
                modelName: modelName,
                citations: citations
            )
        }
    }

    var hasActiveAnswer: Bool { answerMessageID != nil }

    func discardAnswer() {
        guard let answerMessageID else { return }
        switch mode {
        case .newMessage:
            store.removeMessage(answerMessageID, from: sessionID)
        case .regenerate:
            if let activeVersionID {
                store.removeVersion(activeVersionID, from: answerMessageID, in: sessionID)
            }
        }
        self.answerMessageID = nil
        self.activeVersionID = nil
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

    func setMemoryCount(_ count: Int) {
        guard let answerMessageID else { return }
        store.updateMessageMemoryCount(answerMessageID, in: sessionID, memoryCount: count, persist: false)
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
            switch mode {
            case .newMessage:
                store.appendMessage(
                    ChatMessage(role: .assistant, text: text, toolActivities: toolActivities ?? []),
                    to: sessionID
                )
            case .regenerate:
                // No version was begun, so there is nothing to overwrite; a
                // notice avoids appending a stray assistant message.
                store.appendMessage(ChatMessage(role: .system, text: text), to: sessionID)
            }
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

/// Wraps a `StoreTurnOutput` and captures the final answer so a headless
/// Shortcuts run can return it. Every write still lands in the store, so the
/// turn is saved as a normal chat titled from the prompt.
@MainActor
final class CollectingTurnOutput: TurnOutput {
    private let inner: TurnOutput
    private(set) var collectedText = ""

    init(inner: TurnOutput) {
        self.inner = inner
    }

    func beginAnswer(messageID: UUID, citations: [SearchCitation]) {
        inner.beginAnswer(messageID: messageID, citations: citations)
    }

    func discardAnswer() {
        inner.discardAnswer()
    }

    var hasActiveAnswer: Bool { inner.hasActiveAnswer }
    var isFinished: Bool { inner.isFinished }

    func update(text: String, persist: Bool) {
        // Streaming updates are not the final answer; `finish` owns `collectedText`.
        inner.update(text: text, persist: persist)
    }

    func update(thinking: String, duration: Int?, persist: Bool) {
        inner.update(thinking: thinking, duration: duration, persist: persist)
    }

    func setToolActivities(_ activities: [ChatToolActivity], persist: Bool) {
        inner.setToolActivities(activities, persist: persist)
    }

    func setCitations(_ citations: [SearchCitation]) {
        inner.setCitations(citations)
    }

    func setMemoryCount(_ count: Int) {
        inner.setMemoryCount(count)
    }

    func appendNotice(_ text: String) {
        inner.appendNotice(text)
    }

    func finish(text: String, toolActivities: [ChatToolActivity]?, stats: GenerationStats?, duration: Double?) {
        collectedText = text
        inner.finish(text: text, toolActivities: toolActivities, stats: stats, duration: duration)
    }

    func finishWithoutAnswer() {
        inner.finishWithoutAnswer()
    }
}
