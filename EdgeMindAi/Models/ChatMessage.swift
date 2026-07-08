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

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            switch rawValue {
            case Self.system.rawValue, "search":
                self = .system
            case Self.user.rawValue:
                self = .user
            case Self.assistant.rawValue:
                self = .assistant
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown chat message role: \(rawValue)"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    let id: UUID
    let role: Role
    var text: String
    let createdAt: Date
    var citations: [SearchCitation]
    let attachments: [ChatAttachment]
    var toolActivities: [ChatToolActivity]
    /// Raw content of the <think>…</think> block. Updated token-by-token during streaming.
    /// Nil for non-thinking models or when no thinking block is present.
    var thinkingContent: String?
    /// Seconds elapsed from <think> open to </think> close.
    /// Nil while thinking is still in progress; set once </think> is detected.
    var thinkingDurationSeconds: Int?
    var generationDurationSeconds: Double?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = .now,
        citations: [SearchCitation] = [],
        imageData: Data? = nil,
        attachments: [ChatAttachment] = [],
        toolActivities: [ChatToolActivity] = [],
        thinkingContent: String? = nil,
        thinkingDurationSeconds: Int? = nil,
        generationDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.citations = citations
        self.toolActivities = toolActivities
        if attachments.isEmpty, let imageData {
            self.attachments = [.image(imageData)]
        } else {
            self.attachments = attachments
        }
        self.thinkingContent = thinkingContent
        self.thinkingDurationSeconds = thinkingDurationSeconds
        self.generationDurationSeconds = generationDurationSeconds
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
        case toolActivities
        case thinkingContent
        case thinkingDurationSeconds
        case generationDurationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        citations = try container.decodeIfPresent([SearchCitation].self, forKey: .citations) ?? []
        toolActivities = try container.decodeIfPresent([ChatToolActivity].self, forKey: .toolActivities) ?? []
        let decodedAttachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        if decodedAttachments.isEmpty, let legacyImageData = try container.decodeIfPresent(Data.self, forKey: .imageData) {
            attachments = [.image(legacyImageData)]
        } else {
            attachments = decodedAttachments
        }
        thinkingContent = try container.decodeIfPresent(String.self, forKey: .thinkingContent)
        thinkingDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .thinkingDurationSeconds)
        generationDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .generationDurationSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(citations, forKey: .citations)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(toolActivities, forKey: .toolActivities)
        try container.encodeIfPresent(thinkingContent, forKey: .thinkingContent)
        try container.encodeIfPresent(thinkingDurationSeconds, forKey: .thinkingDurationSeconds)
        try container.encodeIfPresent(generationDurationSeconds, forKey: .generationDurationSeconds)
    }
}

struct ChatToolActivity: Identifiable, Hashable, Codable {
    enum Status: String, Hashable, Codable {
        case running
        case completed
        case failed
    }

    let id: UUID
    let name: String
    let displayName: String
    let output: String
    let status: Status
    let createdAt: Date
    let duration: Double?

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        output: String,
        status: Status = .completed,
        createdAt: Date = .now,
        duration: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.output = output
        self.status = status
        self.createdAt = createdAt
        self.duration = duration
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case output
        case status
        case createdAt
        case duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        output = try container.decodeIfPresent(String.self, forKey: .output) ?? ""
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .completed
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(output, forKey: .output)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(duration, forKey: .duration)
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
