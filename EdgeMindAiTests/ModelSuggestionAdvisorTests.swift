import XCTest
@testable import EdgeMindAi

final class ModelSuggestionAdvisorTests: XCTestCase {

    // MARK: fixtures

    private func item(named name: String) -> ModelCatalogItem {
        guard let item = MockCatalogData.items.first(where: { $0.displayName == name }) else {
            fatalError("missing catalog item \(name)")
        }
        return item
    }

    private var compactA: ModelCatalogItem { item(named: "LFM2.5 350M (MLX)") }
    private var compactB: ModelCatalogItem { item(named: "Qwen 3.5 0.8B Instruct (GGUF)") }
    private var compactC: ModelCatalogItem { item(named: "Qwen 3 0.6B (MLX)") }
    private var compactD: ModelCatalogItem { item(named: "LFM2.5 230M Instruct (MLX)") }
    private var standardModel: ModelCatalogItem {
        MockCatalogData.items.first { $0.minimumTier == .standard }!
    }

    private func installed(_ item: ModelCatalogItem) -> InstalledModel {
        InstalledModel(catalogItem: item, installState: .installed, progress: 1, localPath: item.mlxModelID ?? "local")
    }

    private func profile(
        _ item: ModelCatalogItem,
        vision: VisionMode = .none,
        tools: ToolCallFormat? = nil,
        verdict: Verdict = .green
    ) -> RuntimeProfile {
        RuntimeProfile(
            catalogID: item.id,
            verifiedThinking: nil,
            verifiedToolCalling: tools,
            verifiedVision: vision,
            knownLeakTokens: [],
            recommendedMaxTokens: 1024,
            auditedAt: "2026-09-14T00:00:00Z",
            auditVerdict: verdict
        )
    }

    private func profileStore(_ profiles: [RuntimeProfile]) -> RuntimeProfileStore {
        RuntimeProfileStore(bundleLoader: { profiles }, overridePolicy: .disabled)
    }

    private func suggest(
        prompt: String = "",
        hasImage: Bool = false,
        hasDocuments: Bool = false,
        current: ModelCatalogItem?,
        installed items: [ModelCatalogItem],
        profiles: [RuntimeProfile],
        tier: DeviceTier = .compact
    ) -> ModelSuggestion? {
        ModelSuggestionAdvisor.suggestion(
            prompt: prompt,
            hasImage: hasImage,
            hasDocuments: hasDocuments,
            current: current.map(installed),
            installed: items.map(installed),
            profiles: profileStore(profiles),
            tier: tier
        )
    }

    // MARK: vision rule

    func test_imageWithTextOnlyCurrentModel_suggestsVisionModel() {
        let suggestion = suggest(
            hasImage: true,
            current: compactA,
            installed: [compactA, compactB],
            profiles: [profile(compactA, vision: .none), profile(compactB, vision: .imageAndText)]
        )

        XCTAssertEqual(suggestion?.model.catalogItem.id, compactB.id)
        XCTAssertEqual(suggestion?.reason, .vision)
    }

    func test_imageWithVisionCurrentModel_returnsNil() {
        let suggestion = suggest(
            hasImage: true,
            current: compactB,
            installed: [compactB],
            profiles: [profile(compactB, vision: .imageAndText)]
        )

        XCTAssertNil(suggestion)
    }

    func test_imageWithNoVisionCandidateOnTier_returnsNil() {
        let suggestion = suggest(
            hasImage: true,
            current: compactA,
            installed: [compactA, standardModel],
            profiles: [profile(compactA, vision: .none), profile(standardModel, vision: .imageAndText)],
            tier: .compact
        )

        XCTAssertNil(suggestion)
    }

    // MARK: red verdict rule

    func test_redCurrentModel_suggestsGreenModel() {
        let suggestion = suggest(
            current: compactA,
            installed: [compactA, compactB],
            profiles: [
                profile(compactA, verdict: .red("crashes")),
                profile(compactB, verdict: .green)
            ]
        )

        XCTAssertEqual(suggestion?.model.catalogItem.id, compactB.id)
        XCTAssertEqual(suggestion?.reason, .unfitModel)
    }

    func test_yellowCurrentModel_isNotUnfit() {
        let suggestion = suggest(
            current: compactA,
            installed: [compactA, compactB],
            profiles: [
                profile(compactA, verdict: .yellow("slow")),
                profile(compactB, verdict: .green)
            ]
        )

        XCTAssertNil(suggestion)
    }

    func test_redCurrentModelWithNoGreenCandidate_returnsNil() {
        let suggestion = suggest(
            current: compactA,
            installed: [compactA, compactC],
            profiles: [
                profile(compactA, verdict: .red("crashes")),
                profile(compactC, tools: .xmlToolCall, verdict: .red("also crashes"))
            ]
        )

        XCTAssertNil(suggestion)
    }

    // MARK: tooling rule

    func test_toolIntentWithoutToolCalling_suggestsToolModel() {
        let suggestion = suggest(
            prompt: "what is 12 * 12",
            current: compactA,
            installed: [compactA, compactC],
            profiles: [profile(compactA), profile(compactC, tools: .xmlToolCall)]
        )

        XCTAssertEqual(suggestion?.model.catalogItem.id, compactC.id)
        XCTAssertEqual(suggestion?.reason, .tooling)
    }

    func test_documentAttachmentTriggersToolingRule() {
        let suggestion = suggest(
            prompt: "summarize this",
            hasDocuments: true,
            current: compactA,
            installed: [compactA, compactC],
            profiles: [profile(compactA), profile(compactC, tools: .liquidToolCall)]
        )

        XCTAssertEqual(suggestion?.reason, .tooling)
    }

    func test_toolIntentWithVerifiedToolCalling_returnsNil() {
        let suggestion = suggest(
            prompt: "what is 12 * 12",
            current: compactC,
            installed: [compactC],
            profiles: [profile(compactC, tools: .xmlToolCall)]
        )

        XCTAssertNil(suggestion)
    }

    // MARK: priority and ordering

    func test_visionRuleOutranksRedAndTooling() {
        let suggestion = suggest(
            prompt: "what is 12 * 12",
            hasImage: true,
            current: compactA,
            installed: [compactA, compactB, compactC, compactD],
            profiles: [
                profile(compactA, tools: nil, verdict: .red("crashes")),
                profile(compactB, vision: .imageAndText, verdict: .green),
                profile(compactC, tools: .xmlToolCall, verdict: .green),
                profile(compactD, tools: .liquidToolCall, verdict: .green)
            ]
        )

        XCTAssertEqual(suggestion?.reason, .vision)
        XCTAssertEqual(suggestion?.model.catalogItem.id, compactB.id)
    }

    func test_greenCandidatePreferredOverYellow() {
        let suggestion = suggest(
            prompt: "what is 12 * 12",
            current: compactA,
            installed: [compactA, compactC, compactD],
            profiles: [
                profile(compactA),
                profile(compactC, tools: .xmlToolCall, verdict: .yellow("slow")),
                profile(compactD, tools: .liquidToolCall, verdict: .green)
            ]
        )

        XCTAssertEqual(suggestion?.model.catalogItem.id, compactD.id)
    }

    func test_redCandidateIsRankedAfterGreenInToolingRule() {
        // Rule 3 orders candidates (green first) but does not exclude red ones,
        // so a lone tool-verified red model is still the best available.
        let suggestion = suggest(
            prompt: "what is 12 * 12",
            current: compactA,
            installed: [compactA, compactC],
            profiles: [
                profile(compactA),
                profile(compactC, tools: .xmlToolCall, verdict: .red("crashes"))
            ]
        )

        XCTAssertEqual(suggestion?.model.catalogItem.id, compactC.id)
    }

    func test_tierFilterExcludesStandardModelOnCompact() {
        let excluded = suggest(
            prompt: "what is 12 * 12",
            current: compactA,
            installed: [compactA, standardModel],
            profiles: [profile(compactA), profile(standardModel, tools: .xmlToolCall)],
            tier: .compact
        )
        XCTAssertNil(excluded)

        let included = suggest(
            prompt: "what is 12 * 12",
            current: compactA,
            installed: [compactA, standardModel],
            profiles: [profile(compactA), profile(standardModel, tools: .xmlToolCall)],
            tier: .ultra
        )
        XCTAssertEqual(included?.model.catalogItem.id, standardModel.id)
    }

    func test_noInstalledCandidates_returnsNil() {
        let suggestion = ModelSuggestionAdvisor.suggestion(
            prompt: "what is 12 * 12",
            hasImage: true,
            hasDocuments: false,
            current: InstalledModel(catalogItem: compactA, installState: .notInstalled),
            installed: [InstalledModel(catalogItem: compactB, installState: .downloading)],
            profiles: profileStore([profile(compactA), profile(compactB, vision: .imageAndText)]),
            tier: .ultra
        )

        XCTAssertNil(suggestion)
    }
}
