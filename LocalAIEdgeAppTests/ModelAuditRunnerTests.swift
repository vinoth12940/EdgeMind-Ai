import XCTest
@testable import LocalAIEdgeApp

@MainActor
final class ModelAuditRunnerTests: XCTestCase {

    func test_shortFactualCase_passesOnNonEmptyOutput() async {
        let runner = makeRunner(events: [.textDelta("Paris."), .done])
        let model = makeInstalledModel()
        let resolved = makeResolvedModel()
        let auditCase = requireCase("shortFactual")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertTrue(result.pass)
        XCTAssertNil(result.note)
    }

    func test_toolProbe_failsWhenModelDoesNotEmitToolCall() async {
        let runner = makeRunner(events: [.textDelta("It is sunny."), .done])
        let model = makeInstalledModel()
        let resolved = makeResolvedModel(tools: .xmlToolCall)
        let auditCase = requireCase("toolProbe")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertFalse(result.pass)
        XCTAssertEqual(result.note, "tool-call-missing")
    }

    func test_visionProbe_passesWhenAcceptListMatches() async {
        let runner = makeRunner(events: [.textDelta("Apple"), .done])
        let model = makeInstalledModel(supportsVision: true)
        let resolved = makeResolvedModel(vision: .imageAndText)
        let auditCase = requireCase("visionProbe")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertTrue(result.pass)
    }

    func test_leakScan_failsWhenImEndLeaksToFinalText() async {
        let runner = makeRunner(events: [.textDelta("Hello<|im_end|>"), .done])
        let model = makeInstalledModel()
        let resolved = makeResolvedModel()
        let auditCase = requireCase("leakStressor")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertFalse(result.pass)
        XCTAssertEqual(result.note, "leak-token-detected")
    }

    func test_raiSafety_failsWhenUnsafeRequestIsAnswered() async {
        let runner = makeRunner(events: [.textDelta("Here are the steps..."), .done])
        let model = makeInstalledModel()
        let resolved = makeResolvedModel()
        let auditCase = requireCase("raiSafety")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertFalse(result.pass)
        XCTAssertEqual(result.note, "rai-refusal-missing")
    }

    func test_raiSafety_passesWhenModelRefusesAndRedirects() async {
        let runner = makeRunner(events: [.textDelta("I cannot help with that. I can provide safety and legal alternatives."), .done])
        let model = makeInstalledModel()
        let resolved = makeResolvedModel()
        let auditCase = requireCase("raiSafety")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertTrue(result.pass)
        XCTAssertNil(result.note)
    }

    func test_longConversationCaseReceivesHistory() async {
        let service = CapturingInferenceService(events: [.textDelta("Summary"), .done])
        let runner = makeRunner(service: service)
        let model = makeInstalledModel()
        let resolved = makeResolvedModel()
        let auditCase = requireCase("longConversation")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertTrue(result.pass)
        let count = await service.lastConversationCount
        XCTAssertGreaterThan(count, 20)
    }

    func test_documentContextProbeRequiresExpectedText() async {
        let runner = makeRunner(events: [.textDelta("Cedar"), .done])
        let model = makeInstalledModel()
        let resolved = makeResolvedModel()
        let auditCase = requireCase("documentContextProbe")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertTrue(result.pass)
    }

    func test_documentContextProbeFailsWhenAnswerMissesContext() async {
        let runner = makeRunner(events: [.textDelta("I do not know."), .done])
        let model = makeInstalledModel()
        let resolved = makeResolvedModel()
        let auditCase = requireCase("documentContextProbe")

        let result = await runner.runCasePublic(auditCase, model: model, resolved: resolved)

        XCTAssertFalse(result.pass)
        XCTAssertEqual(result.note, "expected-text-missing")
    }

    func test_auditCatalogSkipsRemainingCasesAfterFirstFailure() async {
        let item = makeCatalogItem()
        let runner = ModelAuditRunner(
            inferenceFactory: { _ in ScriptedInferenceService(events: [.done]) },
            downloader: MockAuditDownloader(),
            store: AppStateStore(),
            profileStore: RuntimeProfileStore(bundleLoader: { [] }, overrideLoader: { [] })
        )

        var startedCases: [String] = []
        var skippedCases: [String] = []
        for await progress in await runner.auditCatalog(items: [item], policy: .installIfMissing(diskHeadroomGB: 0)) {
            switch progress {
            case .caseStarted(_, let caseName):
                startedCases.append(caseName)
            case .caseResult(_, let caseName, _, _, let note) where note == "skipped-after-failure":
                skippedCases.append(caseName)
            default:
                break
            }
        }

        XCTAssertEqual(startedCases, ["shortFactual"])
        XCTAssertFalse(skippedCases.isEmpty)
        XCTAssertTrue(skippedCases.contains("longNarrative"))
    }

    func test_sourceVisionProbeCanAuditDisabledSourceVisionModel() async {
        let service = CapturingInferenceService(events: [.textDelta("Apple"), .done])
        let item = makeCatalogItem(supportsVision: false, sourceSupportsVision: true)
        let runner = ModelAuditRunner(
            inferenceFactory: { _ in service },
            downloader: MockAuditDownloader(),
            store: AppStateStore(),
            profileStore: RuntimeProfileStore(bundleLoader: { [] }, overrideLoader: { [] }),
            auditCases: [requireCase("visionProbe")],
            forceSourceVisionProbe: true
        )

        var verdict: Verdict?
        for await progress in await runner.auditCatalog(items: [item], policy: .installIfMissing(diskHeadroomGB: 0)) {
            if case .modelDone(let result) = progress {
                verdict = result.verdict
            }
        }

        XCTAssertEqual(verdict, .green)
        let capturedSupportsVision = await service.lastModelSupportsVision
        XCTAssertTrue(capturedSupportsVision)
    }

    private func makeRunner(events: [StreamEvent]) -> ModelAuditRunner {
        makeRunner(service: ScriptedInferenceService(events: events))
    }

    private func makeRunner(service: any InferenceService) -> ModelAuditRunner {
        let factory: (InstalledModel) -> any InferenceService = { _ in
            service
        }

        return ModelAuditRunner(
            inferenceFactory: factory,
            downloader: MockAuditDownloader(),
            store: AppStateStore(),
            profileStore: RuntimeProfileStore(bundleLoader: { [] }, overrideLoader: { [] })
        )
    }

    private func makeInstalledModel(supportsVision: Bool = false) -> InstalledModel {
        InstalledModel(
            catalogItem: makeCatalogItem(supportsVision: supportsVision),
            installState: .installed,
            progress: 1,
            installedAt: .now,
            localPath: "mlx-community/test-model"
        )
    }

    private func makeCatalogItem(supportsVision: Bool = false, sourceSupportsVision: Bool? = nil) -> ModelCatalogItem {
        ModelCatalogItem(
            displayName: supportsVision ? "Vision Test" : "Test",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Test summary",
            parameterSize: "1.7B",
            quantization: "MLX 4-bit",
            diskSize: "~1.7 GB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/test-model",
            sourceSupportsVision: sourceSupportsVision,
            supportsVision: supportsVision,
            supportsToolCalling: true,
            isThinkingModel: true,
            minimumTier: .standard
        )
    }

    private func makeResolvedModel(
        thinking: ThinkFormat? = nil,
        tools: ToolCallFormat? = nil,
        vision: VisionMode = .none
    ) -> ResolvedModel {
        let catalog = makeCatalogItem(supportsVision: vision == .imageAndText)
        return ResolvedModel(
            catalog: catalog,
            thinking: thinking,
            tools: tools,
            vision: vision,
            leakTokens: RuntimeProfile.safeMinimum(catalogID: catalog.id).knownLeakTokens,
            maxTokens: 512,
            verdict: .green,
            isMismatch: false
        )
    }

    private func requireCase(_ id: String) -> AuditCase {
        guard let auditCase = AuditCaseLibrary.standardCases.first(where: { $0.id == id }) else {
            XCTFail("Missing audit case: \(id)")
            fatalError("Missing audit case: \(id)")
        }
        return auditCase
    }
}

private struct ScriptedInferenceService: InferenceService {
    let events: [StreamEvent]

    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?,
        settings: AppSettings?
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, text: "")
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?,
        settings: AppSettings?
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        let id = UUID()
        return (id, AsyncStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        })
    }
}

private actor CapturingInferenceService: InferenceService {
    let events: [StreamEvent]
    private(set) var lastConversationCount = 0
    private(set) var lastModelSupportsVision = false
    private(set) var lastImageDataPresent = false

    init(events: [StreamEvent]) {
        self.events = events
    }

    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?,
        settings: AppSettings?
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, text: "")
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?,
        settings: AppSettings?
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        lastConversationCount = conversation.count
        lastModelSupportsVision = model.catalogItem.supportsVision
        lastImageDataPresent = imageData != nil
        let id = UUID()
        let events = self.events
        return (id, AsyncStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        })
    }
}
