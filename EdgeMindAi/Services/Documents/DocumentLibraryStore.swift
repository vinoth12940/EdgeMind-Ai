import Foundation
import Observation
import OSLog

private let libraryLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "DocumentLibrary")

/// On-disk document library: `index.json`, `<id>.chunks.json`, and
/// `<id>.vectors.bin` under Application Support/DocumentsLibrary (excluded from
/// backup). Files never leave the device.
@MainActor
@Observable
final class DocumentLibraryStore {
    private(set) var documents: [LibraryDocument]
    private(set) var indexingProgress: [UUID: Double] = [:]

    let directory: URL
    private var cachedIndex: DocumentSearchIndex?
    private let indexer = DocumentIndexer()

    private static let indexFileName = "index.json"

    init(directory: URL? = nil) {
        let resolved = directory ?? Self.defaultDirectory()
        self.directory = resolved
        try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        self.documents = Self.loadIndex(from: resolved)
        Self.excludeFromBackup(resolved)
    }

    // MARK: - Queries

    var readyEnabledDocuments: [LibraryDocument] {
        documents.filter { $0.isEnabled && $0.isReady }
    }

    func document(id: UUID) -> LibraryDocument? {
        documents.first { $0.id == id }
    }

    func chunks(for id: UUID) -> [DocumentChunk] {
        guard let data = try? Data(contentsOf: chunksURL(for: id)),
              let chunks = try? JSONDecoder().decode([DocumentChunk].self, from: data) else {
            return []
        }
        return chunks
    }

    func vectors(for id: UUID) -> DocumentVectors? {
        DocumentVectors(contentsOf: vectorsURL(for: id))
    }

    /// Snapshot used for search and for `ToolContext`. Cached until the library
    /// changes so a chat turn does not re-read every chunks file.
    func searchIndex() -> DocumentSearchIndex {
        if let cachedIndex { return cachedIndex }
        let entries = documents
            .filter { $0.isEnabled && $0.isReady }
            .map { document in
                DocumentSearchIndex.Entry(
                    document: document,
                    chunks: chunks(for: document.id),
                    vectors: vectors(for: document.id)
                )
            }
        let index = DocumentSearchIndex(entries: entries)
        cachedIndex = index
        return index
    }

    // MARK: - Import

    /// Extracts, chunks, and embeds a file, then records it in the index. The
    /// document is visible (with progress) while indexing; deleting it before
    /// completion discards the result.
    @discardableResult
    func importDocument(from url: URL) async -> LibraryDocument? {
        let placeholder = LibraryDocument(
            fileName: url.lastPathComponent,
            kind: .text,
            indexState: .indexing
        )
        upsert(placeholder)
        setIndexingProgress(0.1, for: placeholder.id)

        do {
            let result = try await indexer.index(fileURL: url)
            // The user may have deleted the document while it was indexing.
            guard documents.contains(where: { $0.id == placeholder.id }) else { return nil }
            setIndexingProgress(0.7, for: placeholder.id)
            try write(chunks: result.chunks, for: placeholder.id)
            try write(vectors: result.vectors, for: placeholder.id)
            let document = LibraryDocument(
                id: placeholder.id,
                fileName: result.fileName,
                kind: result.kind,
                importedAt: placeholder.importedAt,
                isEnabled: true,
                chunkCount: result.chunks.count,
                embeddingKind: result.embeddingKind,
                indexState: .ready
            )
            upsert(document)
            clearIndexingProgress(for: placeholder.id)
            return document
        } catch {
            libraryLogger.error("Document indexing failed: \(error.localizedDescription, privacy: .public)")
            var failed = placeholder
            failed.indexState = .failed(error.localizedDescription)
            upsert(failed)
            clearIndexingProgress(for: placeholder.id)
            return nil
        }
    }

    // MARK: - Mutations

    func upsert(_ document: LibraryDocument) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.insert(document, at: 0)
        }
        cachedIndex = nil
        persistIndex()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].isEnabled = enabled
        cachedIndex = nil
        persistIndex()
    }

    func setIndexingProgress(_ progress: Double, for id: UUID) {
        indexingProgress[id] = progress
    }

    func clearIndexingProgress(for id: UUID) {
        indexingProgress[id] = nil
    }

    /// Removes a document and every file it owns.
    func remove(id: UUID) {
        documents.removeAll { $0.id == id }
        indexingProgress[id] = nil
        cachedIndex = nil
        try? FileManager.default.removeItem(at: chunksURL(for: id))
        try? FileManager.default.removeItem(at: vectorsURL(for: id))
        persistIndex()
    }

    func removeAll() {
        for document in documents {
            try? FileManager.default.removeItem(at: chunksURL(for: document.id))
            try? FileManager.default.removeItem(at: vectorsURL(for: document.id))
        }
        documents.removeAll()
        indexingProgress.removeAll()
        cachedIndex = nil
        persistIndex()
    }

    func write(chunks: [DocumentChunk], for id: UUID) throws {
        let data = try JSONEncoder().encode(chunks)
        try data.write(to: chunksURL(for: id), options: .atomic)
        cachedIndex = nil
    }

    func write(vectors: DocumentVectors?, for id: UUID) throws {
        let url = vectorsURL(for: id)
        guard let vectors else {
            try? FileManager.default.removeItem(at: url)
            cachedIndex = nil
            return
        }
        try vectors.write(to: url)
        cachedIndex = nil
    }

    // MARK: - Files

    private func chunksURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).chunks.json")
    }

    private func vectorsURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).vectors.bin")
    }

    private func indexURL() -> URL {
        directory.appendingPathComponent(Self.indexFileName)
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: indexURL(), options: .atomic)
    }

    private static func loadIndex(from directory: URL) -> [LibraryDocument] {
        let url = directory.appendingPathComponent(indexFileName)
        guard let data = try? Data(contentsOf: url),
              let documents = try? JSONDecoder().decode([LibraryDocument].self, from: data) else {
            return []
        }
        return documents
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DocumentsLibrary", isDirectory: true)
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
