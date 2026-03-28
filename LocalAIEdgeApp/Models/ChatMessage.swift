import Foundation

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable, Hashable {
        case system
        case user
        case assistant
        case search
    }

    let id: UUID
    let role: Role
    var text: String
    let createdAt: Date
    let citations: [SearchCitation]
    let imageData: Data?
    /// Raw content of the <think>…</think> block. Updated token-by-token during streaming.
    /// Nil for non-thinking models or when no thinking block is present.
    var thinkingContent: String?
    /// Seconds elapsed from <think> open to </think> close.
    /// Nil while thinking is still in progress; set once </think> is detected.
    var thinkingDurationSeconds: Int?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = .now,
        citations: [SearchCitation] = [],
        imageData: Data? = nil,
        thinkingContent: String? = nil,
        thinkingDurationSeconds: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.citations = citations
        self.imageData = imageData
        self.thinkingContent = thinkingContent
        self.thinkingDurationSeconds = thinkingDurationSeconds
    }
}

struct SearchCitation: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let url: URL
    let snippet: String

    init(id: UUID = UUID(), title: String, url: URL, snippet: String) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}
