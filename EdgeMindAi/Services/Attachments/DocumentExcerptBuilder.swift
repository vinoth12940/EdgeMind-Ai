import Foundation

/// Selects the most *relevant* part of a long document instead of blindly keeping
/// its first N characters.
///
/// Small-context runtimes (LiteRT-LM caps at 2048 tokens, so roughly 1,600
/// characters of inlined document) used to receive only the head of a document,
/// which silently dropped the answer when the useful content sat further in.
/// This chunks the text and keeps the highest-scoring chunks for the user's
/// question, preserving their original order.
enum DocumentExcerptBuilder {

    /// Returns at most `maxCharacters` of `text`.
    ///
    /// - If the text already fits, it is returned unchanged.
    /// - With a usable `query`, the best-matching chunks are kept.
    /// - Otherwise it falls back to a head+tail trim.
    static func excerpt(from text: String, maxCharacters: Int, query: String) -> String {
        guard maxCharacters > 0 else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }

        let queryTerms = DocumentSearchService.tokenize(query)
        guard !queryTerms.isEmpty else {
            return InferenceBudget.trimHistoryText(trimmed, maxCharacters: maxCharacters)
        }

        let chunks = DocumentChunker.chunksWithLineRanges(from: trimmed)
        guard chunks.count > 1 else {
            return InferenceBudget.trimHistoryText(trimmed, maxCharacters: maxCharacters)
        }

        let scores = DocumentSearchService.bm25(
            queryTerms: queryTerms,
            documents: chunks.map { DocumentSearchService.tokenize($0.text) }
        )

        // Best-scoring chunk first, then fill the budget in that order.
        let ranked = chunks.indices.sorted { lhs, rhs in
            if scores[lhs] != scores[rhs] { return scores[lhs] > scores[rhs] }
            return lhs < rhs
        }

        var selected: [Int] = []
        var used = 0
        for index in ranked {
            let chunk = chunks[index]
            let cost = chunk.text.count + 2
            if used + cost > maxCharacters, !selected.isEmpty { continue }
            guard used + cost <= maxCharacters || selected.isEmpty else { break }
            selected.append(index)
            used += cost
            if used >= maxCharacters { break }
        }

        guard !selected.isEmpty else {
            return InferenceBudget.trimHistoryText(trimmed, maxCharacters: maxCharacters)
        }

        // Relevant chunks in reading order, joined without inventing text.
        let ordered = selected.sorted()
        let body = ordered
            .map { chunks[$0].text }
            .joined(separator: "\n…\n")

        let marker = "[Excerpted the \(ordered.count) most relevant part(s) of \(chunks.count) for this question.]"
        // Reserve room for the marker, which is prepended — prefixing the body to the
        // full budget and then adding the marker pushed the result over maxCharacters.
        let bodyBudget = max(0, maxCharacters - marker.count - 1)
        // Too little room to carry any content: emitting just the marker would waste
        // the caller's budget on a note about nothing.
        guard bodyBudget >= 32 else { return "" }
        let excerpt = String(body.prefix(bodyBudget))
        return marker + "\n" + excerpt
    }
}
