import Foundation

/// Shared container used to hand files and text from the Share Extension to the
/// app. Only the share inbox lives here — chat sessions, settings, and installed
/// models stay in the app's own container (spec §1).
enum AppGroup {
    static let identifier = "group.com.vinothrajalingam.EdgeMindAi"

    /// The App Group container, or nil when the entitlement is missing (for
    /// example in unit tests or a misconfigured build).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var inboxURL: URL? {
        guard let containerURL else { return nil }
        return containerURL.appendingPathComponent("Inbox", isDirectory: true)
    }
}

enum ShareAction: String, Codable, Hashable, CaseIterable {
    case summarize
    case explain
    case ask

    var displayName: String {
        switch self {
        case .summarize: return "Summarize"
        case .explain: return "Explain"
        case .ask: return "Ask"
        }
    }

    var promptPrefix: String {
        switch self {
        case .summarize: return "Summarize the shared content."
        case .explain: return "Explain the shared content."
        case .ask: return ""
        }
    }
}

/// One shared item waiting to be imported by the app.
struct SharePayload: Codable, Hashable, Identifiable {
    let id: UUID
    let action: ShareAction
    /// Required for `.ask`.
    let question: String?
    /// Shared text or URL string. URLs are passed as text; the app never fetches them.
    let text: String?
    /// Name of the copied file inside the item folder, when a file was shared.
    let fileName: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        action: ShareAction,
        question: String? = nil,
        text: String? = nil,
        fileName: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.action = action
        self.question = question
        self.text = text
        self.fileName = fileName
        self.createdAt = createdAt
    }

    /// The prompt the app should send for this payload.
    var resolvedPrompt: String {
        let question = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch action {
        case .ask:
            return question.isEmpty ? (text ?? "") : question
        case .summarize, .explain:
            return action.promptPrefix
        }
    }
}
