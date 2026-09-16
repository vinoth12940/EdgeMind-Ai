import XCTest
@testable import EdgeMindAi

@MainActor
final class DocumentSearchTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentSearchTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: fixtures

    private func document(_ name: String, enabled: Bool = true, state: LibraryDocument.IndexState = .ready) -> LibraryDocument {
        LibraryDocument(fileName: name, kind: .text, isEnabled: enabled, indexState: state)
    }

    private func entry(
        _ document: LibraryDocument,
        chunks: [(text: String, page: Int?)],
        vectors: (kind: DocumentEmbeddingKind, rows: [[Float]])? = nil
    ) -> DocumentSearchIndex.Entry {
        DocumentSearchIndex.Entry(
            document: document,
            chunks: chunks.enumerated().map { index, chunk in
                DocumentChunk(index: index, text: chunk.text, pageNumber: chunk.page)
            },
            vectors: vectors.map {
                DocumentVectors(kind: $0.kind, dimension: $0.rows.first?.count ?? 0, vectors: $0.rows)
            }
        )
    }

    // MARK: ranking

    func test_vectorSimilarityRanksMatchingChunkFirst() {
        let doc = document("a.txt")
        let index = DocumentSearchIndex(entries: [
            entry(doc, chunks: [("unrelated words", nil), ("more unrelated", nil)],
                  vectors: (.contextual, [[1, 0], [0, 1]]))
        ])

        let hits = DocumentSearchService.search(query: "zzz", index: index) { _ in [1, 0] }

        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].text, "unrelated words")
        XCTAssertEqual(hits[0].score, 0.7, accuracy: 0.0001)
    }

    func test_keywordOnlyDocumentUsesBM25Alone() {
        let keywordOnly = document("notes.txt")
        let vectorDoc = document("pic.txt")
        let index = DocumentSearchIndex(entries: [
            entry(keywordOnly, chunks: [("the invoice total is 42", nil)]),
            entry(vectorDoc, chunks: [("nothing relevant", nil)], vectors: (.sentence, [[1, 0]]))
        ])

        let hits = DocumentSearchService.search(query: "invoice", index: index) { _ in [0, 1] }

        let best = try? XCTUnwrap(hits.first)
        XCTAssertEqual(best?.fileName, "notes.txt")
        XCTAssertEqual(best?.score ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(hits.count, 1)
    }

    func test_resultsCarryPageNumberAndFileName() {
        let doc = document("report.pdf")
        let index = DocumentSearchIndex(entries: [
            entry(doc, chunks: [("budget figures", 12)])
        ])

        let hits = DocumentSearchService.search(query: "budget", index: index)

        XCTAssertEqual(hits.first?.fileName, "report.pdf")
        XCTAssertEqual(hits.first?.pageNumber, 12)
    }

    func test_limitCapsResults() {
        let doc = document("big.txt")
        let chunks = (0..<10).map { ("alpha passage \($0)", nil as Int?) }
        let index = DocumentSearchIndex(entries: [entry(doc, chunks: chunks)])

        let hits = DocumentSearchService.search(query: "alpha", index: index, limit: 3)

        XCTAssertEqual(hits.count, 3)
    }

    func test_emptyIndexAndEmptyQuery_returnNoHits() {
        XCTAssertTrue(DocumentSearchService.search(query: "alpha", index: .empty).isEmpty)
        let doc = document("a.txt")
        let index = DocumentSearchIndex(entries: [entry(doc, chunks: [("alpha", nil)])])
        XCTAssertTrue(DocumentSearchService.search(query: "   ", index: index).isEmpty)
    }

    func test_disabledAndUnreadyDocumentsAreExcludedFromStoreIndex() throws {
        let store = DocumentLibraryStore(directory: directory)
        let enabled = document("enabled.txt")
        let disabled = document("disabled.txt", enabled: false)
        let indexing = document("indexing.txt", state: .indexing)
        let failed = document("failed.txt", state: .failed("nope"))

        for doc in [enabled, disabled, indexing, failed] {
            store.upsert(doc)
            try store.write(chunks: [DocumentChunk(index: 0, text: "alpha content")], for: doc.id)
        }

        let index = store.searchIndex()

        XCTAssertEqual(index.entries.map(\.document.fileName), ["enabled.txt"])
        let hits = DocumentSearchService.search(query: "alpha", index: index)
        XCTAssertEqual(hits.map(\.fileName), ["enabled.txt"])
    }

    func test_storeIndexInvalidatedWhenDocumentDisabled() throws {
        let store = DocumentLibraryStore(directory: directory)
        let doc = document("doc.txt")
        store.upsert(doc)
        try store.write(chunks: [DocumentChunk(index: 0, text: "alpha")], for: doc.id)

        XCTAssertEqual(store.searchIndex().entries.count, 1)
        store.setEnabled(false, for: doc.id)
        XCTAssertEqual(store.searchIndex().entries.count, 0)
    }

    // MARK: rendering

    func test_renderHits_labelsPageAndFileName() {
        let hits = [
            DocumentHit(documentID: UUID(), fileName: "report.pdf", pageNumber: 3, text: "budget", score: 1),
            DocumentHit(documentID: UUID(), fileName: "notes.txt", pageNumber: nil, text: "memo", score: 0.5)
        ]

        let rendered = DocumentSearchService.renderHits(hits, budgetCharacters: 1_000)

        XCTAssertTrue(rendered.contains("[report.pdf p.3] budget"))
        XCTAssertTrue(rendered.contains("[notes.txt] memo"))
    }

    func test_renderHits_respectsCharacterBudget() {
        let hits = (0..<5).map { _ in
            DocumentHit(documentID: UUID(), fileName: "f.txt", pageNumber: nil, text: String(repeating: "x", count: 100), score: 1)
        }

        let rendered = DocumentSearchService.renderHits(hits, budgetCharacters: 220)

        XCTAssertEqual(rendered.components(separatedBy: "\n\n").count, 2)
    }

    // MARK: vectors file

    func test_vectorsRoundTripThroughFile() throws {
        let vectors = DocumentVectors(kind: .sentence, dimension: 3, vectors: [[1, 2, 3], [4, 5, 6]])
        let url = directory.appendingPathComponent("v.bin")

        try vectors.write(to: url)
        let reloaded = try XCTUnwrap(DocumentVectors(contentsOf: url))

        XCTAssertEqual(reloaded.kind, .sentence)
        XCTAssertEqual(reloaded.dimension, 3)
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.vector(at: 0), [1, 2, 3])
        XCTAssertEqual(reloaded.vector(at: 1), [4, 5, 6])
        XCTAssertNil(reloaded.vector(at: 2))
    }

    func test_vectorsFileIsMappedAndRejectsGarbage() throws {
        let url = directory.appendingPathComponent("bad.bin")
        try Data([0x01, 0x02]).write(to: url)
        XCTAssertNil(DocumentVectors(contentsOf: url))
    }

    // MARK: tool integration

    func test_searchDocumentsToolReturnsLabeledPassagesAndCitations() async {
        let doc = document("handbook.pdf")
        let index = DocumentSearchIndex(entries: [
            entry(doc, chunks: [("vacation policy is 20 days", 7)])
        ])
        let context = ToolContext(
            settings: .default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil,
            documentSearchIndex: index
        )

        let result = await SearchDocumentsTool().run(argsJSON: "{\"query\": \"vacation\"}", context: context)

        XCTAssertTrue(result.output.contains("[handbook.pdf p.7]"))
        XCTAssertEqual(result.citations.count, 1)
        XCTAssertEqual(result.citations.first?.title, "handbook.pdf — p.7")
    }

    func test_searchDocumentsToolErrorsWhenFeatureDisabled() async {
        let doc = document("handbook.pdf")
        let index = DocumentSearchIndex(entries: [entry(doc, chunks: [("vacation policy", nil)])])
        var settings = AppSettings.default
        settings.documentSearchEnabled = false
        let context = ToolContext(
            settings: settings,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil,
            documentSearchIndex: index
        )

        let result = await SearchDocumentsTool().run(argsJSON: "{\"query\": \"vacation\"}", context: context)

        XCTAssertTrue(result.output.hasPrefix("Error:"))
    }

    // MARK: - Argument shapes
    //
    // Apple Intelligence sends a BARE STRING for arguments
    // (`{"name": "search_documents", "arguments": "vacation policy"}`). Missing that
    // case made every Apple Intelligence document search fail with a "query
    // required" error, so the model told the user to upload the document instead.

    func test_extractQuery_toleratesEveryModelShape() {
        // Flat top-level key.
        XCTAssertEqual(SearchDocumentsTool.extractQuery(#"{"query":"vacation policy"}"#), "vacation policy")
        // Nested arguments object.
        XCTAssertEqual(SearchDocumentsTool.extractQuery(#"{"arguments":{"query":"vacation policy"}}"#), "vacation policy")
        // JSON encoded as a string.
        XCTAssertEqual(
            SearchDocumentsTool.extractQuery(#"{"arguments":"{\"query\":\"vacation policy\"}"}"#),
            "vacation policy"
        )
        // Bare value inside a JSON envelope.
        XCTAssertEqual(SearchDocumentsTool.extractQuery(#"{"arguments":"vacation policy"}"#), "vacation policy")
        // Bare string — the Apple Intelligence shape.
        XCTAssertEqual(SearchDocumentsTool.extractQuery("vacation policy"), "vacation policy")
    }

    func test_extractQuery_rejectsEmptyOrUnrelated() {
        XCTAssertNil(SearchDocumentsTool.extractQuery(""))
        XCTAssertNil(SearchDocumentsTool.extractQuery("{}"))
        XCTAssertNil(SearchDocumentsTool.extractQuery(#"{"arguments":""}"#))
    }
}
