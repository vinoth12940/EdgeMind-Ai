import Foundation
import NaturalLanguage

/// Splits extracted document text into overlapping chunks for indexing. Pure and
/// deterministic so it can be unit tested without the NaturalLanguage stack where
/// sentence tokenization is unavailable (it falls back to paragraph/hard cuts).
enum DocumentChunker {
    /// Target chunk length in characters (spec §3).
    static let targetLength = 800
    /// Characters of the previous chunk repeated at the start of the next.
    static let overlap = 150

    /// Chunks plain text. `pageNumber` is attached to every chunk (PDFs).
    static func chunks(from text: String, pageNumber: Int? = nil) -> [DocumentChunk] {
        let units = splitIntoUnits(text, pageNumber: pageNumber)
        return pack(units)
    }

    /// Chunks a page-addressable document, keeping each chunk's page number.
    static func chunks(fromPages pages: [String]) -> [DocumentChunk] {
        var result: [DocumentChunk] = []
        for (offset, page) in pages.enumerated() {
            let pageChunks = chunks(from: page, pageNumber: offset + 1)
            let base = result.count
            result.append(contentsOf: pageChunks.enumerated().map { index, chunk in
                DocumentChunk(
                    index: base + index,
                    text: chunk.text,
                    pageNumber: chunk.pageNumber,
                    lineRange: nil
                )
            })
        }
        return result.enumerated().map { index, chunk in
            DocumentChunk(index: index, text: chunk.text, pageNumber: chunk.pageNumber, lineRange: chunk.lineRange)
        }
    }

    /// Chunks text while preserving line numbers (plain text / CSV / Markdown).
    static func chunksWithLineRanges(from text: String) -> [DocumentChunk] {
        let units = splitIntoLineUnits(text)
        return pack(units)
    }

    // MARK: - Internals

    private struct Unit {
        let text: String
        let pageNumber: Int?
        let lineRange: ClosedRange<Int>?
    }

    private static func splitIntoUnits(_ text: String, pageNumber: Int?) -> [Unit] {
        paragraphs(in: text).flatMap { paragraph -> [Unit] in
            splitParagraph(paragraph, pageNumber: pageNumber, lineRange: nil)
        }
    }

    private static func splitIntoLineUnits(_ text: String) -> [Unit] {
        let lines = text.components(separatedBy: .newlines)
        var units: [Unit] = []
        var buffer: [String] = []
        var bufferStart = 1

        func flush(endLine: Int) {
            guard !buffer.isEmpty else { return }
            let paragraph = buffer.joined(separator: "\n")
            let range = bufferStart...max(bufferStart, endLine)
            units.append(contentsOf: splitParagraph(paragraph, pageNumber: nil, lineRange: range))
            buffer.removeAll()
        }

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush(endLine: lineNumber - 1)
                bufferStart = lineNumber + 1
            } else {
                if buffer.isEmpty { bufferStart = lineNumber }
                buffer.append(line)
            }
        }
        flush(endLine: lines.count)
        return units
    }

    private static func splitParagraph(_ paragraph: String, pageNumber: Int?, lineRange: ClosedRange<Int>?) -> [Unit] {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.count <= targetLength {
            return [Unit(text: trimmed, pageNumber: pageNumber, lineRange: lineRange)]
        }

        var units: [Unit] = []
        for sentence in sentences(in: trimmed) {
            if sentence.count <= targetLength {
                units.append(Unit(text: sentence, pageNumber: pageNumber, lineRange: lineRange))
            } else {
                units.append(contentsOf: hardCut(sentence).map {
                    Unit(text: $0, pageNumber: pageNumber, lineRange: lineRange)
                })
            }
        }
        return units
    }

    private static func paragraphs(in text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result.isEmpty ? [text] : result
    }

    private static func hardCut(_ text: String) -> [String] {
        var pieces: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: targetLength, limitedBy: text.endIndex) ?? text.endIndex
            let piece = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            start = end
        }
        return pieces
    }

    /// Greedily packs units into chunks no longer than `targetLength`, seeding
    /// each new chunk with the tail of the previous one for context continuity.
    private static func pack(_ units: [Unit]) -> [DocumentChunk] {
        guard !units.isEmpty else { return [] }

        var chunks: [DocumentChunk] = []
        var current = ""
        var currentPage: Int?
        var currentRange: ClosedRange<Int>?

        func flush() {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            chunks.append(DocumentChunk(index: chunks.count, text: text, pageNumber: currentPage, lineRange: currentRange))
        }

        for unit in units {
            // A page change always starts a new chunk so page labels stay honest.
            if !current.isEmpty, let currentPage, let unitPage = unit.pageNumber, unitPage != currentPage {
                flush()
                current = ""
            }

            if current.isEmpty {
                current = unit.text
                currentPage = unit.pageNumber
                currentRange = unit.lineRange
                continue
            }

            let candidate = current + "\n\n" + unit.text
            if candidate.count <= targetLength {
                current = candidate
                currentRange = merge(currentRange, unit.lineRange)
            } else {
                flush()
                // Shrink the overlap when the next unit is already near the target
                // so a chunk never exceeds `targetLength`.
                let allowedOverlap = max(0, min(overlap, targetLength - unit.text.count - 2))
                let tail = allowedOverlap > 0
                    ? String(current.suffix(allowedOverlap)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                current = tail.isEmpty ? unit.text : tail + "\n\n" + unit.text
                currentPage = unit.pageNumber
                currentRange = unit.lineRange
            }
        }
        flush()

        return chunks.enumerated().map { index, chunk in
            DocumentChunk(index: index, text: chunk.text, pageNumber: chunk.pageNumber, lineRange: chunk.lineRange)
        }
    }

    private static func merge(_ lhs: ClosedRange<Int>?, _ rhs: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return min(lhs.lowerBound, rhs.lowerBound)...max(lhs.upperBound, rhs.upperBound)
    }
}
