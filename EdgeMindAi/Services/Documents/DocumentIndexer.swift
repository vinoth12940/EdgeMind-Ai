import Foundation
import NaturalLanguage

/// Extracts, chunks, and embeds a document off the main actor. The caller
/// (`DocumentLibraryStore`) owns persistence and progress reporting.
actor DocumentIndexer {
    struct Result: Sendable {
        let fileName: String
        let kind: ChatAttachment.Kind
        let chunks: [DocumentChunk]
        let vectors: DocumentVectors?
        let embeddingKind: DocumentEmbeddingKind
    }

    enum IndexError: LocalizedError {
        case emptyDocument
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .emptyDocument: return "No readable text was found in this file."
            case .unreadable(let detail): return detail
            }
        }
    }

    /// Indexes a file URL end to end.
    func index(fileURL: URL) throws -> Result {
        let extracted: (fileName: String, kind: ChatAttachment.Kind, pages: [String])
        do {
            extracted = try DocumentExtractionService.libraryPages(from: fileURL)
        } catch {
            throw IndexError.unreadable(error.localizedDescription)
        }
        return try index(fileName: extracted.fileName, kind: extracted.kind, pages: extracted.pages)
    }

    /// Chunks and embeds already-extracted pages.
    func index(fileName: String, kind: ChatAttachment.Kind, pages: [String]) throws -> Result {
        let usablePages = pages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usablePages.isEmpty else { throw IndexError.emptyDocument }

        let chunks: [DocumentChunk]
        if usablePages.count == 1 && kind != .pdf {
            // Plain text keeps line ranges so hits can point at a region.
            let text = usablePages[0]
            let lineChunks = DocumentChunker.chunksWithLineRanges(from: text)
            chunks = lineChunks.isEmpty ? DocumentChunker.chunks(from: text) : lineChunks
        } else {
            chunks = DocumentChunker.chunks(fromPages: usablePages)
        }
        guard !chunks.isEmpty else { throw IndexError.emptyDocument }

        let sample = String(usablePages.joined(separator: "\n").prefix(2_000))
        let language = DocumentEmbedder.language(of: sample)
        let embeddings = DocumentEmbedder.embed(chunks.map(\.text), language: language)

        let vectors: DocumentVectors?
        if embeddings.kind == .none || embeddings.vectors.count != chunks.count || embeddings.dimension == 0 {
            vectors = nil
        } else {
            vectors = DocumentVectors(kind: embeddings.kind, dimension: embeddings.dimension, vectors: embeddings.vectors)
        }

        return Result(
            fileName: fileName,
            kind: kind,
            chunks: chunks,
            vectors: vectors,
            embeddingKind: vectors?.kind ?? .none
        )
    }

    /// Embeds a single session-scoped attachment (long chat attachment path).
    func indexAttachment(_ attachment: ChatAttachment) throws -> Result {
        let text = attachment.extractedText ?? ""
        return try index(fileName: attachment.fileName, kind: attachment.kind, pages: [text])
    }
}
