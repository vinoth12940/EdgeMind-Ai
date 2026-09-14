import Foundation
import NaturalLanguage

/// A snapshot of everything searchable in the library. Value type so `ToolContext`
/// can carry it across actor boundaries without touching disk.
struct DocumentSearchIndex: Sendable {
    struct Entry: Sendable {
        let document: LibraryDocument
        let chunks: [DocumentChunk]
        let vectors: DocumentVectors?
    }

    let entries: [Entry]

    static let empty = DocumentSearchIndex(entries: [])

    var isEmpty: Bool { entries.allSatisfy { $0.chunks.isEmpty } }
    var chunkCount: Int { entries.reduce(0) { $0 + $1.chunks.count } }
}

/// Ranks document chunks against a query. Pure apart from Apple's on-device
/// embedding lookup, so the scoring path is unit-testable with a stub index.
enum DocumentSearchService {
    static let defaultLimit = 5

    /// App entry point: ranks the live library snapshot.
    @MainActor
    static func search(query: String, library: DocumentLibraryStore, limit: Int = defaultLimit) -> [DocumentHit] {
        search(query: query, index: library.searchIndex(), limit: limit)
    }

    /// Ranks `index` against `query`.
    ///
    /// Score = `0.7 × cosine + 0.3 × normalized BM25` when the document has
    /// vectors; keyword-only documents use normalized BM25 alone (spec §3).
    /// `queryVectorProvider` is injectable so scoring is testable without the
    /// NaturalLanguage embedding stack.
    static func search(
        query: String,
        index: DocumentSearchIndex,
        limit: Int = defaultLimit,
        queryVectorProvider: ((DocumentEmbeddingKind) -> [Float]?)? = nil
    ) -> [DocumentHit] {
        let queryTerms = tokenize(query)
        guard !queryTerms.isEmpty, !index.isEmpty else { return [] }

        let vectorProvider = queryVectorProvider ?? { kind in
            DocumentEmbedder.embedQuery(query, kind: kind, language: DocumentEmbedder.language(of: query))
        }

        // Flatten every chunk so BM25 statistics span the whole library.
        var flat: [(entry: DocumentSearchIndex.Entry, chunk: DocumentChunk, tokens: [String])] = []
        for entry in index.entries {
            for chunk in entry.chunks {
                flat.append((entry, chunk, tokenize(chunk.text)))
            }
        }
        guard !flat.isEmpty else { return [] }

        let bm25Scores = bm25(queryTerms: queryTerms, documents: flat.map(\.tokens))
        let maxBM25 = bm25Scores.max() ?? 0

        var hits: [DocumentHit] = []
        for (offset, item) in flat.enumerated() {
            let normalizedBM25 = maxBM25 > 0 ? bm25Scores[offset] / maxBM25 : 0
            var score = normalizedBM25

            if let vectors = item.entry.vectors,
               !vectors.isEmpty,
               let queryVector = vectorProvider(vectors.kind),
               queryVector.count == vectors.dimension,
               let chunkVector = vectors.vector(at: item.chunk.index) {
                let cosine = max(0, cosineSimilarity(queryVector, chunkVector))
                score = 0.7 * cosine + 0.3 * normalizedBM25
            }

            guard score > 0 else { continue }
            hits.append(DocumentHit(
                documentID: item.entry.document.id,
                fileName: item.entry.document.fileName,
                pageNumber: item.chunk.pageNumber,
                text: item.chunk.text,
                score: score
            ))
        }

        return hits
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.documentID.uuidString < rhs.documentID.uuidString
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Builds the label-prefixed prompt block for a set of hits.
    static func renderHits(_ hits: [DocumentHit], budgetCharacters: Int) -> String {
        guard !hits.isEmpty, budgetCharacters > 0 else { return "" }
        var blocks: [String] = []
        var used = 0
        for hit in hits {
            let label = hit.pageNumber.map { "\(hit.fileName) p.\($0)" } ?? hit.fileName
            let block = "[\(label)] \(hit.text)"
            if used + block.count > budgetCharacters, !blocks.isEmpty { break }
            blocks.append(block)
            used += block.count
        }
        return blocks.joined(separator: "\n\n")
    }

    // MARK: - Scoring helpers

    private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Double = 0
        var lhsMagnitude: Double = 0
        var rhsMagnitude: Double = 0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            dot += left * right
            lhsMagnitude += left * left
            rhsMagnitude += right * right
        }
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return 0 }
        return dot / (lhsMagnitude.squareRoot() * rhsMagnitude.squareRoot())
    }

    /// Okapi BM25 with k1 = 1.2, b = 0.75.
    static func bm25(queryTerms: [String], documents: [[String]]) -> [Double] {
        let k1 = 1.2
        let b = 0.75
        let count = documents.count
        guard count > 0 else { return [] }

        let lengths = documents.map(\.count)
        let averageLength = Double(lengths.reduce(0, +)) / Double(count)
        guard averageLength > 0 else { return Array(repeating: 0, count: count) }

        // Document frequency per query term.
        var documentFrequency: [String: Int] = [:]
        for term in Set(queryTerms) {
            documentFrequency[term] = documents.reduce(0) { partial, tokens in
                partial + (tokens.contains(term) ? 1 : 0)
            }
        }

        return documents.enumerated().map { offset, tokens in
            let length = Double(tokens.count)
            var score = 0.0
            var termFrequency: [String: Int] = [:]
            for token in tokens where queryTerms.contains(token) {
                termFrequency[token, default: 0] += 1
            }
            for (term, frequency) in termFrequency {
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (Double(count) - df + 0.5) / (df + 0.5))
                let tf = Double(frequency)
                let denominator = tf + k1 * (1 - b + b * length / averageLength)
                score += idf * (tf * (k1 + 1)) / denominator
            }
            return score
        }
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
