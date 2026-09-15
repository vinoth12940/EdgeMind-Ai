import XCTest
@testable import EdgeMindAi

/// Guards the invariant that an assembled prompt always fits the model's safe
/// context window — for **every** catalog model, not just LiteRT.
///
/// Regression: attaching a PDF with `Gemma 4 E2B Instruct (LiteRT-LM)` failed at
/// runtime with `INVALID_ARGUMENT: Input token ids are too long: 2265 >= 2048`
/// because the document was inlined up to a flat 20,000 characters and nothing
/// checked the total against the 2048-token LiteRT cap.
final class PromptBudgetTests: XCTestCase {

    // MARK: - Fixtures

    private func model(named name: String) -> InstalledModel {
        let item = MockCatalogData.items.first { $0.displayName == name }!
        return InstalledModel(
            catalogItem: item,
            installState: .installed,
            progress: 1,
            localPath: item.mlxModelID ?? "local"
        )
    }

    private var liteRTModel: InstalledModel {
        model(named: "Gemma 4 E2B Instruct (LiteRT-LM)")
    }

    /// A deliberately huge document, the shape that triggered the bug.
    private func giantAttachment(characters: Int = 200_000) -> ChatAttachment {
        ChatAttachment(
            kind: .pdf,
            fileName: "State Farm Insurance Card.pdf",
            mimeType: "application/pdf",
            extractedText: String(repeating: "insurance policy coverage detail ", count: characters / 33)
        )
    }

    private func assembledPrompt(
        for model: InstalledModel,
        documentCharacters: Int,
        historyTurns: Int = 24,
        historyTurnCharacters: Int = 4_000
    ) -> (system: String, history: [String], current: String) {
        let system = AppSettings.default.systemPrompt
            + ToolRegistry.renderPromptSection(for: [CalculateTool(), GetCurrentTimeTool()])
        let documentContext = DocumentExtractionService.promptContext(
            from: [giantAttachment(characters: documentCharacters)],
            maxCharacters: InferenceBudget.documentContextBudget(for: model)
        )
        let history = (0..<historyTurns).map { index in
            "Turn \(index) " + String(repeating: "y", count: historyTurnCharacters)
        }
        return (system, history, "Summarize this.\n\n" + documentContext)
    }

    private func totalTokens(system: String, history: [String], current: String) -> Int {
        InferenceBudget.estimatedTokens(system)
            + InferenceBudget.estimatedTokens(current)
            + history.reduce(0) { $0 + InferenceBudget.estimatedTokens($1) }
    }

    // MARK: - The invariant, across every catalog model

    func test_everyCatalogModel_fitsItsWorstCasePrompt() {
        XCTAssertEqual(MockCatalogData.items.count, 46, "catalog size changed; keep this sweep exhaustive")

        for item in MockCatalogData.items {
            let installed = InstalledModel(
                catalogItem: item,
                installState: .installed,
                progress: 1,
                localPath: item.mlxModelID ?? "local"
            )
            let prompt = assembledPrompt(for: installed, documentCharacters: 200_000)
            let fitted = InferenceBudget.fitPrompt(
                system: prompt.system,
                history: prompt.history,
                current: prompt.current,
                for: installed
            )

            let used = totalTokens(system: prompt.system, history: fitted.history, current: fitted.current)
            let headroom = InferenceBudget.maxGeneratedTokens(for: installed, searchContext: nil)
            let window = InferenceBudget.safeContextWindow(for: installed)

            XCTAssertLessThanOrEqual(
                used + headroom,
                window,
                "\(item.displayName) (\(item.runtimeType)) overflows: prompt \(used) + generated \(headroom) > window \(window)"
            )
        }
    }

    // MARK: - The reported bug

    func test_liteRTHasASmallHardCap() {
        // The failure came from this cap; if it ever changes, revisit the fix.
        XCTAssertEqual(InferenceBudget.safeContextWindow(for: liteRTModel), 2_048)
    }

    func test_unboundedDocumentContext_wouldStillOverflowLiteRT() {
        // Proves the fix is load-bearing: the old flat 20,000-character inline
        // exceeds the whole LiteRT window on its own.
        let unbounded = DocumentExtractionService.promptContext(
            from: [giantAttachment()],
            maxCharacters: 20_000
        )
        XCTAssertGreaterThan(
            InferenceBudget.estimatedTokens(unbounded),
            InferenceBudget.safeContextWindow(for: liteRTModel),
            "20k characters should not fit in a 2048-token window"
        )
    }

    func test_documentContext_isBoundedByTheModelBudget() {
        let context = DocumentExtractionService.promptContext(
            from: [giantAttachment()],
            maxCharacters: InferenceBudget.documentContextBudget(for: liteRTModel)
        )

        XCTAssertLessThanOrEqual(
            context.count,
            InferenceBudget.documentContextBudget(for: liteRTModel),
            "inlined document text must respect the character budget"
        )
        // And it still carries the document label so the model knows the source.
        XCTAssertTrue(context.contains("State Farm Insurance Card.pdf"))
    }

    func test_documentContext_keepsEveryAttachmentWithinBudget() {
        let attachments = (0..<3).map { index in
            ChatAttachment(
                kind: .text,
                fileName: "doc\(index).txt",
                mimeType: "text/plain",
                extractedText: String(repeating: "z", count: 50_000)
            )
        }

        let context = DocumentExtractionService.promptContext(from: attachments, maxCharacters: 3_000)

        XCTAssertLessThanOrEqual(context.count, 3_000)
        XCTAssertTrue(context.contains("doc0.txt"))
    }

    func test_fitPrompt_trimsCurrentTurnBeforeDroppingHistory() {
        let model = liteRTModel
        let current = "Question.\n\n" + String(repeating: "x", count: 50_000)
        let history = (0..<5).map { "history \($0) " + String(repeating: "h", count: 2_000) }

        let fitted = InferenceBudget.fitPrompt(
            system: "system",
            history: history,
            current: current,
            for: model
        )

        XCTAssertLessThan(fitted.current.count, current.count, "current turn should be trimmed")
        XCTAssertTrue(fitted.current.hasPrefix("Question."), "the question itself must survive")
    }

    func test_fitPrompt_dropsOldestHistoryWhenNeeded() {
        let model = liteRTModel
        let history = (0..<20).map { "turn \($0) " + String(repeating: "h", count: 1_500) }

        let fitted = InferenceBudget.fitPrompt(
            system: "system",
            history: history,
            current: "short question",
            for: model
        )

        XCTAssertLessThan(fitted.history.count, history.count)
        // Whatever survives is the most recent suffix.
        XCTAssertEqual(fitted.history, Array(history.suffix(fitted.history.count)))
    }

    func test_fitPrompt_leavesShortPromptsUntouched() {
        let model = liteRTModel
        let history = ["a", "b"]
        let fitted = InferenceBudget.fitPrompt(
            system: "system",
            history: history,
            current: "hi",
            for: model
        )

        XCTAssertEqual(fitted.history, history)
        XCTAssertEqual(fitted.current, "hi")
    }

    func test_promptCharacterBudget_scalesWithTheContextWindow() {
        XCTAssertGreaterThan(
            InferenceBudget.promptCharacterBudget(for: model(named: "Granite 3.3 2B Instruct (MLX)")),
            InferenceBudget.promptCharacterBudget(for: liteRTModel)
        )
    }
}
