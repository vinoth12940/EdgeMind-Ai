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

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = .now,
        citations: [SearchCitation] = [],
        imageData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.citations = citations
        self.imageData = imageData
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
