import Foundation
import NaturalLanguage

/// Turns text into vectors using Apple's on-device NaturalLanguage embeddings.
/// Preference order (spec §3): `NLContextualEmbedding` (mean-pooled) →
/// `NLEmbedding.sentenceEmbedding` → none (keyword-only search). No user content
/// leaves the device; asset downloads are system-managed.
enum DocumentEmbedder {

    struct Embeddings {
        let kind: DocumentEmbeddingKind
        let dimension: Int
        let vectors: [[Float]]
    }

    /// Best embedding kind currently usable for a language, without triggering
    /// an asset download.
    static func bestKind(for language: NLLanguage) -> DocumentEmbeddingKind {
        if contextualEmbedding(for: language) != nil { return .contextual }
        if NLEmbedding.sentenceEmbedding(for: language) != nil { return .sentence }
        return .none
    }

    /// Embeds every text with the best available kind. Returns `.none` with no
    /// vectors when no embedding is available.
    static func embed(_ texts: [String], language: NLLanguage) -> Embeddings {
        guard !texts.isEmpty else { return Embeddings(kind: .none, dimension: 0, vectors: []) }

        if let embedding = contextualEmbedding(for: language) {
            var vectors: [[Float]] = []
            var dimension = 0
            for text in texts {
                guard let vector = contextualVector(for: text, language: language, using: embedding) else { continue }
                dimension = vector.count
                vectors.append(vector)
            }
            if !vectors.isEmpty {
                return Embeddings(kind: .contextual, dimension: dimension, vectors: vectors)
            }
        }

        if let embedding = NLEmbedding.sentenceEmbedding(for: language) {
            let vectors = texts.compactMap { text -> [Float]? in
                guard let vector = embedding.vector(for: text) else { return nil }
                return vector.map(Float.init)
            }
            if !vectors.isEmpty {
                return Embeddings(kind: .sentence, dimension: vectors[0].count, vectors: vectors)
            }
        }

        return Embeddings(kind: .none, dimension: 0, vectors: [])
    }

    /// Embeds a query with the same kind a document was indexed with. Returns nil
    /// when that kind is no longer available, so the caller can fall back to BM25.
    static func embedQuery(_ query: String, kind: DocumentEmbeddingKind, language: NLLanguage) -> [Float]? {
        switch kind {
        case .contextual:
            guard let embedding = contextualEmbedding(for: language) else { return nil }
            return contextualVector(for: query, language: language, using: embedding)
        case .sentence:
            guard let embedding = NLEmbedding.sentenceEmbedding(for: language),
                  let vector = embedding.vector(for: query) else { return nil }
            return vector.map(Float.init)
        case .none:
            return nil
        }
    }

    /// Detects the dominant language of the text, defaulting to English.
    static func language(of text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2_000)))
        return recognizer.dominantLanguage ?? .english
    }

    // MARK: - Contextual embedding

    private static func contextualEmbedding(for language: NLLanguage) -> NLContextualEmbedding? {
        guard let embedding = NLContextualEmbedding(language: language) else { return nil }
        // `requestEmbeddingAssets` would download; indexing must work offline, so
        // only use the model when its assets are already present.
        guard embedding.hasAvailableAssets else { return nil }
        return embedding
    }

    private static func contextualVector(for text: String, language: NLLanguage, using embedding: NLContextualEmbedding) -> [Float]? {
        guard let result = try? embedding.embeddingResult(for: text, language: language) else {
            return nil
        }
        var sum: [Double] = []
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            if sum.isEmpty {
                sum = [Double](repeating: 0, count: vector.count)
            }
            guard vector.count == sum.count else { return true }
            for index in vector.indices { sum[index] += vector[index] }
            count += 1
            return true
        }
        guard count > 0, !sum.isEmpty else { return nil }
        return sum.map { Float($0 / Double(count)) }
    }
}
