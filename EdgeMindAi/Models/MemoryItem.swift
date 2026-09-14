import Foundation

/// One saved personal memory. Rendered into the model's system prompt as part of
/// the `# About the user` section while `isEnabled` is true.
struct MemoryItem: Identifiable, Hashable, Codable {
    /// Hard cap on a memory's length (spec §1).
    static let maxTextCharacters = 200

    let id: UUID
    var text: String
    var isEnabled: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        isEnabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.text = Self.clamped(text)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    static func clamped(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTextCharacters else { return trimmed }
        return String(trimmed.prefix(maxTextCharacters))
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isEnabled, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = Self.clamped(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
