import XCTest
@testable import EdgeMindAi

/// Verifies the on-demand document reader tool. The model can pull extracted text
/// from an attached document instead of having it pre-injected into the prompt.
final class ReadDocumentToolTests: XCTestCase {

    func test_readsExtractedTextFromAttachedDocument() async throws {
        let doc = ChatAttachment(
            kind: .markdown,
            fileName: "notes.md",
            mimeType: "text/markdown",
            extractedText: "# Meeting\nDecide on the launch date."
        )
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [doc],
            installedModel: nil
        )
        let result = await ReadDocumentTool().run(argsJSON: "{}", context: ctx)
        XCTAssertTrue(result.output.contains("notes.md"), "Got: \(result.output)")
        XCTAssertTrue(result.output.contains("Meeting"))
        XCTAssertTrue(result.output.contains("launch date"))
    }

    func test_returnsErrorWhenNoDocumentAttached() async throws {
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [],
            installedModel: nil
        )
        let result = await ReadDocumentTool().run(argsJSON: "{}", context: ctx)
        XCTAssertTrue(result.output.contains("Error"), "Got: \(result.output)")
        XCTAssertTrue(result.output.contains("No readable documents"))
    }

    func test_filtersOutImageAttachments() async throws {
        // An image attachment is NOT a readable document for this tool.
        let image = ChatAttachment(kind: .image, fileName: "photo.jpg", mimeType: "image/jpeg")
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [image],
            installedModel: nil
        )
        let result = await ReadDocumentTool().run(argsJSON: "{}", context: ctx)
        XCTAssertTrue(result.output.contains("Error"), "Got: \(result.output)")
    }

    func test_picksSpecificDocumentByName() async throws {
        let docs = [
            ChatAttachment(kind: .pdf, fileName: "report.pdf", mimeType: "application/pdf", extractedText: "Quarterly report content"),
            ChatAttachment(kind: .text, fileName: "todo.txt", mimeType: "text/plain", extractedText: "Buy groceries")
        ]
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: docs,
            installedModel: nil
        )
        let result = await ReadDocumentTool().run(argsJSON: "{\"file_name\": \"todo\"}", context: ctx)
        XCTAssertTrue(result.output.contains("todo.txt"))
        XCTAssertTrue(result.output.contains("groceries"))
        XCTAssertFalse(result.output.contains("report.pdf"))
    }

    func test_errorWhenRequestedFileNameNotFound() async throws {
        let doc = ChatAttachment(kind: .pdf, fileName: "report.pdf", mimeType: "application/pdf", extractedText: "x")
        let ctx = ToolContext(
            settings: AppSettings.default,
            conversation: [],
            chatSessions: [],
            attachedDocuments: [doc],
            installedModel: nil
        )
        let result = await ReadDocumentTool().run(argsJSON: "{\"file_name\": \"missing.doc\"}", context: ctx)
        XCTAssertTrue(result.output.contains("Error"), "Got: \(result.output)")
        XCTAssertTrue(result.output.contains("report.pdf"), "Should list available docs in the error")
    }
}
