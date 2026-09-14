import Foundation

/// How a document's vectors were produced. Queries use the same kind as the
/// document they are compared against.
enum DocumentEmbeddingKind: String, Codable, Hashable {
    /// `NLContextualEmbedding`, mean-pooled. Highest quality.
    case contextual
    /// `NLEmbedding.sentenceEmbedding`.
    case sentence
    /// No vectors available; the document is searchable by keyword (BM25) only.
    case none
}

/// One indexed document in the on-device library.
struct LibraryDocument: Identifiable, Hashable, Codable {
    enum IndexState: Hashable {
        case indexing
        case ready
        case failed(String)
    }

    let id: UUID
    var fileName: String
    var kind: ChatAttachment.Kind
    var importedAt: Date
    var isEnabled: Bool
    var chunkCount: Int
    var embeddingKind: DocumentEmbeddingKind
    var indexState: IndexState

    init(
        id: UUID = UUID(),
        fileName: String,
        kind: ChatAttachment.Kind,
        importedAt: Date = .now,
        isEnabled: Bool = true,
        chunkCount: Int = 0,
        embeddingKind: DocumentEmbeddingKind = .none,
        indexState: IndexState = .indexing
    ) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.importedAt = importedAt
        self.isEnabled = isEnabled
        self.chunkCount = chunkCount
        self.embeddingKind = embeddingKind
        self.indexState = indexState
    }

    var isReady: Bool {
        if case .ready = indexState { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case id, fileName, kind, importedAt, isEnabled, chunkCount, embeddingKind, indexState
    }

    private enum StateKeys: String, CodingKey {
        case status, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? "Document"
        kind = try container.decodeIfPresent(ChatAttachment.Kind.self, forKey: .kind) ?? .text
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? .now
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        chunkCount = try container.decodeIfPresent(Int.self, forKey: .chunkCount) ?? 0
        embeddingKind = try container.decodeIfPresent(DocumentEmbeddingKind.self, forKey: .embeddingKind) ?? .none
        let state = try container.nestedContainer(keyedBy: StateKeys.self, forKey: .indexState)
        let status = try state.decodeIfPresent(String.self, forKey: .status) ?? "failed"
        switch status {
        case "indexing": indexState = .indexing
        case "ready": indexState = .ready
        default: indexState = .failed(try state.decodeIfPresent(String.self, forKey: .message) ?? "Unknown error")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(kind, forKey: .kind)
        try container.encode(importedAt, forKey: .importedAt)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(chunkCount, forKey: .chunkCount)
        try container.encode(embeddingKind, forKey: .embeddingKind)
        var state = container.nestedContainer(keyedBy: StateKeys.self, forKey: .indexState)
        switch indexState {
        case .indexing:
            try state.encode("indexing", forKey: .status)
        case .ready:
            try state.encode("ready", forKey: .status)
        case .failed(let message):
            try state.encode("failed", forKey: .status)
            try state.encode(message, forKey: .message)
        }
    }
}

/// One searchable slice of a document.
struct DocumentChunk: Identifiable, Hashable, Codable {
    let index: Int
    let text: String
    let pageNumber: Int?
    let lineRange: ClosedRange<Int>?

    var id: Int { index }

    init(index: Int, text: String, pageNumber: Int? = nil, lineRange: ClosedRange<Int>? = nil) {
        self.index = index
        self.text = text
        self.pageNumber = pageNumber
        self.lineRange = lineRange
    }

    /// Compact label used when chunks are injected into a prompt.
    var sourceLabel: String {
        if let pageNumber { return "p.\(pageNumber)" }
        if let lineRange { return "lines \(lineRange.lowerBound)-\(lineRange.upperBound)" }
        return "chunk \(index + 1)"
    }
}

/// A scored search result.
struct DocumentHit: Hashable {
    let documentID: UUID
    let fileName: String
    let pageNumber: Int?
    let text: String
    let score: Double
}
