import XCTest
import SwiftUI
import UIKit
@testable import EdgeMindAi

/// Regression tests for the inline Markdown run parser.
///
/// The original implementation appended one `Text` per character and concatenated them.
/// SwiftUI resolves a concatenated `Text` recursively, once per node, so a line longer
/// than roughly 670 characters exhausted the 1 MB main-thread stack on device and killed
/// the app with `SIGSEGV` — the reported "app crashes when I open it" (a restored chat
/// message was long enough to tip it over). These tests pin the run budget that prevents it.
final class InlineMarkdownParserTests: XCTestCase {

    // MARK: - Run budget

    func test_plainProseIsASingleRun() {
        let runs = InlineMarkdownParser.runs(from: "Just an ordinary sentence.", citationCount: 0)
        XCTAssertEqual(runs, [.plain("Just an ordinary sentence.")])
    }

    func test_longPlainTextCollapsesToASingleRun() {
        let text = String(repeating: "a", count: 5_000)
        let runs = InlineMarkdownParser.runs(from: text, citationCount: 0)
        XCTAssertEqual(runs.count, 1, "Long prose must not produce one Text node per character")
        XCTAssertEqual(runs.first, .plain(text))
    }

    func test_runCountIsBoundedForVeryLongTextWithMarkup() {
        // ~40k characters of alternating emphasis: thousands of potential runs.
        let text = String(repeating: "**bold** and `code` text. ", count: 1_500)
        let runs = InlineMarkdownParser.runs(from: text, citationCount: 0)

        XCTAssertLessThanOrEqual(
            runs.count,
            InlineMarkdownParser.maxStyledRuns + 3,
            "Run count must stay bounded regardless of input length"
        )
    }

    func test_runCountIsBoundedForAdversarialInputs() {
        let inputs = [
            String(repeating: "a", count: 100_000),
            String(repeating: "*", count: 20_000),
            String(repeating: "`", count: 20_000),
            String(repeating: "~~", count: 10_000),
            String(repeating: "[1]", count: 10_000),
            String(repeating: "**x**", count: 10_000),
            String(repeating: "[a](https://example.com) ", count: 5_000),
            String(repeating: "🙂", count: 20_000)
        ]

        for input in inputs {
            let runs = InlineMarkdownParser.runs(from: input, citationCount: 10_000)
            XCTAssertLessThanOrEqual(
                runs.count,
                InlineMarkdownParser.maxStyledRuns + 3,
                "Unbounded run count for input of length \(input.count)"
            )
        }
    }

    func test_contentAfterTheBudgetCutoffIsPreservedVerbatim() {
        // Past the budget the remainder renders unstyled — but nothing may be dropped.
        let unit = "**b** plain "
        let text = String(repeating: unit, count: 2_000)
        let runs = InlineMarkdownParser.runs(from: text, citationCount: 0)

        let rebuilt = runs.map(\.text).joined()
        XCTAssertTrue(
            rebuilt.hasSuffix(String(repeating: unit, count: 1_000)),
            "Text after the budget cutoff must be emitted verbatim"
        )
        XCTAssertEqual(
            rebuilt.components(separatedBy: "plain").count - 1,
            2_000,
            "Every plain word must survive the budget cutoff"
        )
        XCTAssertLessThanOrEqual(runs.count, InlineMarkdownParser.maxStyledRuns + 3)
    }

    func test_emptyInputProducesNoRuns() {
        XCTAssertTrue(InlineMarkdownParser.runs(from: "", citationCount: 0).isEmpty)
    }

    // MARK: - Inline syntax

    func test_boldItalicCodeAndStrikethrough() {
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "a **b** c", citationCount: 0),
            [.plain("a "), .bold("b"), .plain(" c")]
        )
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "a *b* c", citationCount: 0),
            [.plain("a "), .italic("b"), .plain(" c")]
        )
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "a `b` c", citationCount: 0),
            [.plain("a "), .code("b"), .plain(" c")]
        )
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "a ~~b~~ c", citationCount: 0),
            [.plain("a "), .strikethrough("b"), .plain(" c")]
        )
    }

    func test_plainTextAroundMarkupIsCoalesced() {
        let runs = InlineMarkdownParser.runs(
            from: "The quick brown fox **jumps** over the lazy dog",
            citationCount: 0
        )
        XCTAssertEqual(
            runs,
            [.plain("The quick brown fox "), .bold("jumps"), .plain(" over the lazy dog")]
        )
        XCTAssertEqual(runs.count, 3, "Plain spans must be one run each, not one per character")
    }

    func test_link() {
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "see [docs](https://example.com) now", citationCount: 0),
            [
                .plain("see "),
                .link(text: "docs", url: "https://example.com"),
                .plain(" now")
            ]
        )
    }

    func test_invalidLinkFallsBackToPlainText() {
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "[docs]()", citationCount: 0),
            [.plain("[docs]()")]
        )
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "[unclosed", citationCount: 0),
            [.plain("[unclosed")]
        )
    }

    func test_citationBadge() {
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "fact [2] here", citationCount: 3),
            [.plain("fact "), .plain(" "), .citationBadge("2"), .plain(" "), .plain(" here")]
        )
    }

    func test_citationBeyondAvailableRangeStaysPlain() {
        XCTAssertEqual(
            InlineMarkdownParser.runs(from: "fact [9]", citationCount: 3),
            [.plain("fact [9]")]
        )
    }

    func test_loneMarkersStayPlainText() {
        XCTAssertEqual(InlineMarkdownParser.runs(from: "*", citationCount: 0), [.plain("*")])
        XCTAssertEqual(InlineMarkdownParser.runs(from: "[", citationCount: 0), [.plain("[")])
        XCTAssertEqual(InlineMarkdownParser.runs(from: "`", citationCount: 0), [.plain("`")])
    }

    func test_emojiAreNotSplit() {
        XCTAssertEqual(InlineMarkdownParser.runs(from: "ok 🙂 done", citationCount: 0), [.plain("ok 🙂 done")])
    }
}

/// Renders `MarkdownTextView` for real. Without the run budget these tests overflow the
/// main-thread stack and take the whole test runner down with them, which is exactly what
/// used to happen on device.
final class MarkdownTextViewStackSafetyTests: XCTestCase {

    private var window: UIWindow?
    private var host: UIHostingController<AnyView>?

    override func tearDown() {
        host?.view.removeFromSuperview()
        window?.isHidden = true
        window?.rootViewController = nil
        host = nil
        window = nil
        super.tearDown()
    }

    private func render(_ text: String, isUser: Bool = false, citations: [SearchCitation] = []) -> CGSize {
        let host = UIHostingController(rootView: AnyView(
            MarkdownTextView(text: text, isUser: isUser, citations: citations)
                .textSelection(.enabled)
                .frame(width: 340, alignment: .leading)
        ))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Measure as well, so SwiftUI is forced to actually resolve the concatenated
        // `Text` — resolving it is the recursive step that used to blow the stack.
        let size = host.sizeThatFits(in: CGSize(width: 340, height: CGFloat.greatestFiniteMagnitude))

        window.isHidden = true
        self.host = host
        self.window = window
        return size
    }

    func test_rendersALongMessageWithoutOverflowingTheStack() {
        // Far longer than the ~670-runs ceiling that killed the 1 MB device main-thread stack.
        let size = render(String(repeating: "This is a plain sentence of prose. ", count: 1_000))
        XCTAssertGreaterThan(size.height, 100, "The message should have been laid out")
    }

    func test_rendersALongMessageWithMarkup() {
        let size = render(String(repeating: "**Heading** wrapped in *emphasis* and `code`. ", count: 800))
        XCTAssertGreaterThan(size.height, 100, "The message should have been laid out")
    }

    func test_rendersALongUserMessageWithCitations() {
        let citations = (1...5).map { index in
            SearchCitation(
                title: "Source \(index)",
                url: URL(string: "https://example.com/\(index)")!,
                snippet: "Snippet \(index)"
            )
        }
        let size = render(String(repeating: "Answer [1] and [2] with detail. ", count: 800), citations: citations)
        XCTAssertGreaterThan(size.height, 100, "The message should have been laid out")
    }

    func test_rendersTheRestoredSessionMessageThatUsedToCrash() {
        // Verbatim shape of the message restored from the device that reproduced the crash.
        let summary = """
        The H4 approval notice confirms the temporary stay of SANKARI SADASIVAM from \
        October 1, 2024, to April 10, 2027. The applicant is authorized to stay based on \
        the principal alien's approved petition. The notice lists the receipt number, the \
        priority date, and the notice date, and states that the petition was approved. \
        Please review the document carefully and compare the dates against your own records \
        before relying on any of the details summarised here.
        """
        let size = render(summary)
        XCTAssertGreaterThan(size.height, 10, "The restored message should have been laid out")
    }
}
