import XCTest
@testable import EdgeMindAi

final class DocumentChunkerTests: XCTestCase {
    private func paragraph(_ length: Int, seed: Character) -> String {
        String(repeating: String(seed), count: length)
    }

    func test_shortText_producesSingleChunk() {
        let chunks = DocumentChunker.chunks(from: "A short note about Kyoto.")

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].index, 0)
        XCTAssertEqual(chunks[0].text, "A short note about Kyoto.")
        XCTAssertNil(chunks[0].pageNumber)
    }

    func test_emptyText_producesNoChunks() {
        XCTAssertTrue(DocumentChunker.chunks(from: "   \n\n  ").isEmpty)
    }

    func test_allChunksRespectTargetLength() {
        // One 4,000-character paragraph: must be sentence/hard split.
        let text = String(repeating: "word ", count: 800)

        let chunks = DocumentChunker.chunks(from: text)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.text.count, DocumentChunker.targetLength)
        }
    }

    func test_veryLongSingleParagraph_isHardCut() {
        let text = String(repeating: "x", count: DocumentChunker.targetLength * 3 + 40)

        let chunks = DocumentChunker.chunks(from: text)

        XCTAssertEqual(chunks.count, 4)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.text.count, DocumentChunker.targetLength)
        }
    }

    func test_consecutiveChunksCarryOverlap() {
        let first = paragraph(500, seed: "a")
        let second = paragraph(500, seed: "b")

        let chunks = DocumentChunker.chunks(from: first + "\n\n" + second)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].text, first)
        XCTAssertTrue(chunks[1].text.hasSuffix(second))
        // The head of the second chunk repeats the tail of the first.
        XCTAssertLessThan(DocumentChunker.overlap, chunks[1].text.count)
        XCTAssertTrue(chunks[1].text.hasPrefix(String(first.suffix(DocumentChunker.overlap))))
    }

    func test_paragraphsThatFitTogether_shareOneChunk() {
        let text = "First paragraph.\n\nSecond paragraph."

        let chunks = DocumentChunker.chunks(from: text)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].text.contains("First paragraph."))
        XCTAssertTrue(chunks[0].text.contains("Second paragraph."))
    }

    func test_pages_keepPageNumbers() {
        let pages = [
            "Page one content.",
            "Page two content.",
            "Page three content."
        ]

        let chunks = DocumentChunker.chunks(fromPages: pages)

        XCTAssertEqual(chunks.map(\.pageNumber), [1, 2, 3])
        XCTAssertEqual(chunks.map(\.index), [0, 1, 2])
    }

    func test_pageChange_startsNewChunk() {
        let pages = [paragraph(400, seed: "a"), paragraph(400, seed: "b")]

        let chunks = DocumentChunker.chunks(fromPages: pages)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].pageNumber, 1)
        XCTAssertEqual(chunks[1].pageNumber, 2)
        // Cross-page chunks would mislabel sources, so the first page's tail must
        // not leak into the second page's first chunk.
        XCTAssertFalse(chunks[1].text.contains(paragraph(200, seed: "a")))
    }

    func test_lineRanges_arePreserved() {
        let text = "line one\nline two\nline three"

        let chunks = DocumentChunker.chunksWithLineRanges(from: text)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].lineRange, 1...3)
    }

    func test_lineRanges_spanBlankSeparatedParagraphsWhenPackedTogether() {
        let text = "line one\nline two\nline three\n\nline five"

        let chunks = DocumentChunker.chunksWithLineRanges(from: text)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].lineRange, 1...5)
    }

    func test_sourceLabel_prefersPageThenLines() {
        XCTAssertEqual(DocumentChunk(index: 0, text: "x", pageNumber: 4).sourceLabel, "p.4")
        XCTAssertEqual(DocumentChunk(index: 0, text: "x", lineRange: 2...9).sourceLabel, "lines 2-9")
        XCTAssertEqual(DocumentChunk(index: 2, text: "x").sourceLabel, "chunk 3")
    }
}
