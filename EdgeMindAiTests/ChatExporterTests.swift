import XCTest
@testable import EdgeMindAi

final class ChatExporterTests: XCTestCase {
    private func makeSession() -> ChatSession {
        ChatSession(
            title: "Trip Planning",
            modelID: nil,
            messages: [
                ChatMessage(role: .user, text: "Where should I go in Japan?"),
                ChatMessage(
                    role: .assistant,
                    text: "Kyoto in spring is lovely.",
                    citations: [
                        SearchCitation(
                            title: "Kyoto Guide",
                            url: URL(string: "https://example.com/kyoto")!,
                            snippet: "Cherry blossoms peak in early April."
                        )
                    ],
                    attachments: [.image(Data([0x01, 0x02]))],
                    toolActivities: [
                        ChatToolActivity(name: "web_search", displayName: "Searched web", output: "kyoto")
                    ],
                    thinkingContent: "Consider the season and the crowds.",
                    thinkingDurationSeconds: 3,
                    generationDurationSeconds: 1.2,
                    stats: GenerationStats(totalDuration: 1.2)
                )
            ]
        )
    }

    func test_markdown_hasStructureRolesAndSources() {
        let markdown = ChatExporter.markdown(session: makeSession(), includeThinking: false)

        XCTAssertTrue(markdown.hasPrefix("# Trip Planning"))
        XCTAssertTrue(markdown.contains("## You"))
        XCTAssertTrue(markdown.contains("## Assistant"))
        XCTAssertTrue(markdown.contains("Where should I go in Japan?"))
        XCTAssertTrue(markdown.contains("Kyoto in spring is lovely."))
        XCTAssertTrue(markdown.contains("### Sources"))
        XCTAssertTrue(markdown.contains("[Kyoto Guide](https://example.com/kyoto)"))
        XCTAssertTrue(markdown.contains("Cherry blossoms peak in early April."))
        XCTAssertTrue(markdown.contains("_[image attached]_"))
    }

    func test_markdown_thinkingToggleControlsThinkingSection() {
        let without = ChatExporter.markdown(session: makeSession(), includeThinking: false)
        let with = ChatExporter.markdown(session: makeSession(), includeThinking: true)

        XCTAssertFalse(without.contains("### Thinking"))
        XCTAssertFalse(without.contains("Consider the season"))
        XCTAssertTrue(with.contains("### Thinking"))
        XCTAssertTrue(with.contains("Consider the season and the crowds."))
    }

    func test_markdown_skipsSystemMessages() {
        var session = makeSession()
        session.messages.insert(ChatMessage(role: .system, text: "⚠️ Retrying"), at: 0)

        let markdown = ChatExporter.markdown(session: session, includeThinking: false)

        XCTAssertFalse(markdown.contains("⚠️ Retrying"))
    }

    func test_export_markdown_writesUTF8File() async throws {
        let url = try await ChatExporter.export(session: makeSession(), format: .markdown, includeThinking: false)

        XCTAssertEqual(url.pathExtension, "md")
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("# Trip Planning"))
    }

    func test_export_pdf_writesNonEmptyPDF() async throws {
        let url = try await ChatExporter.export(session: makeSession(), format: .pdf, includeThinking: true)

        XCTAssertEqual(url.pathExtension, "pdf")
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
    }

    func test_pdf_matchesMarkdownCoverage_whenThinkingIncluded() async throws {
        let withoutThinking = try await ChatExporter.export(session: makeSession(), format: .pdf, includeThinking: false)
        let withThinking = try await ChatExporter.export(session: makeSession(), format: .pdf, includeThinking: true)

        let plain = try Data(contentsOf: withoutThinking)
        let rich = try Data(contentsOf: withThinking)
        // Thinking text adds content, so the richer export must not be smaller.
        XCTAssertGreaterThanOrEqual(rich.count, plain.count)
    }
}
