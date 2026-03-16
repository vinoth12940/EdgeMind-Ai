import Foundation

struct ChatSession: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    let modelID: UUID?
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        modelID: UUID?,
        messages: [ChatMessage],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.modelID = modelID
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
