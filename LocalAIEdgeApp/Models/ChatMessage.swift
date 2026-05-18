import Foundation

struct ChatAttachment: Identifiable, Hashable, Codable {
    enum Kind: String, Hashable, Codable {
        case image
        case text
        case pdf
        case csv
        case markdown
    }

    let id: UUID
    var kind: Kind
    var fileName: String
    var mimeType: String
    var rawData: Data?
    var extractedText: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        fileName: String,
        mimeType: String,
        rawData: Data? = nil,
        extractedText: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.rawData = rawData
        self.extractedText = extractedText
        self.createdAt = createdAt
    }

    static func image(_ data: Data, fileName: String = "image.jpg") -> ChatAttachment {
        ChatAttachment(kind: .image, fileName: fileName, mimeType: "image/jpeg", rawData: data)
    }

    var imageData: Data? {
        kind == .image ? rawData : nil
    }

    var displayLabel: String {
        switch kind {
        case .image: return "Image"
        case .text: return "Text"
        case .pdf: return "PDF"
        case .csv: return "CSV"
        case .markdown: return "Markdown"
        }
    }

    func sanitized(maxRawBytes: Int, maxExtractedCharacters: Int) -> ChatAttachment {
        var copy = self
        if let rawData, rawData.count > maxRawBytes {
            copy.rawData = nil
        }
        if let extractedText, extractedText.count > maxExtractedCharacters {
            copy.extractedText = String(extractedText.prefix(maxExtractedCharacters))
        }
        return copy
    }
}

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
    let attachments: [ChatAttachment]
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
        attachments: [ChatAttachment] = [],
        thinkingContent: String? = nil,
        thinkingDurationSeconds: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.citations = citations
        if attachments.isEmpty, let imageData {
            self.attachments = [.image(imageData)]
        } else {
            self.attachments = attachments
        }
        self.thinkingContent = thinkingContent
        self.thinkingDurationSeconds = thinkingDurationSeconds
    }

    var imageData: Data? {
        attachments.lazy.compactMap(\.imageData).first
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case createdAt
        case citations
        case imageData
        case attachments
        case thinkingContent
        case thinkingDurationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        citations = try container.decodeIfPresent([SearchCitation].self, forKey: .citations) ?? []
        let decodedAttachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        if decodedAttachments.isEmpty, let legacyImageData = try container.decodeIfPresent(Data.self, forKey: .imageData) {
            attachments = [.image(legacyImageData)]
        } else {
            attachments = decodedAttachments
        }
        thinkingContent = try container.decodeIfPresent(String.self, forKey: .thinkingContent)
        thinkingDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .thinkingDurationSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(citations, forKey: .citations)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(thinkingContent, forKey: .thinkingContent)
        try container.encodeIfPresent(thinkingDurationSeconds, forKey: .thinkingDurationSeconds)
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
