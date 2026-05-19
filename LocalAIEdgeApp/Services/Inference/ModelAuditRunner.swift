import Foundation
import OSLog
import UIKit

actor ModelAuditRunner {
    private static let caseTimeoutNanoseconds: UInt64 = 120_000_000_000
    private static let maxAuditOutputCharacters = 2_000

    private let inferenceFactory: (InstalledModel) -> any InferenceService
    private let downloader: AuditDownloader
    private let store: AppStateStore
    private let profileStore: RuntimeProfileStore
    private let auditCases: [AuditCase]
    private let forceSourceVisionProbe: Bool
    private let reportRunID: String
    private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "ModelAuditRunner")

    init(
        inferenceFactory: @escaping (InstalledModel) -> any InferenceService,
        downloader: AuditDownloader,
        store: AppStateStore,
        profileStore: RuntimeProfileStore,
        auditCases: [AuditCase] = AuditCaseLibrary.standardCases,
        forceSourceVisionProbe: Bool = false
    ) {
        self.inferenceFactory = inferenceFactory
        self.downloader = downloader
        self.store = store
        self.profileStore = profileStore
        self.auditCases = auditCases
        self.forceSourceVisionProbe = forceSourceVisionProbe
        self.reportRunID = Self.nowIso()
    }

    func auditCatalog(items: [ModelCatalogItem], policy: InstallPolicy) -> AsyncStream<AuditProgress> {
        AsyncStream { continuation in
            Task {
                for item in items {
                    await auditOne(item: item, policy: policy, continuation: continuation)
                }
                continuation.yield(.runFinished)
                continuation.finish()
            }
        }
    }

    private func auditOne(
        item: ModelCatalogItem,
        policy: InstallPolicy,
        continuation: AsyncStream<AuditProgress>.Continuation
    ) async {
        let auditItem = catalogItemForAudit(item)
        let resolved = resolvedModelForAudit(auditItem)
        let applicableCases = auditCases.filter { $0.appliesWhen(resolved) }
        var caseResults: [String: Bool] = [:]
        var notes: [String: String] = [:]

        let existing = await downloader.installedModel(for: auditItem, store: store)
        var model: InstalledModel
        var mustUninstall = false

        switch (existing, policy) {
        case (let installed?, _):
            model = installed.withCatalogItem(auditItem)

        case (nil, .requireInstalled):
            for auditCase in applicableCases {
                caseResults[auditCase.id] = false
                notes[auditCase.id] = "not-installed"
                continuation.yield(.caseResult(
                    modelName: item.displayName,
                    caseName: auditCase.id,
                    pass: false,
                    durationMs: 0,
                    note: "not-installed"
                ))
            }
            let result = ModelAuditResult(
                modelID: item.id,
                displayName: item.displayName,
                verdict: .yellow("not-installed"),
                caseResults: caseResults,
                notes: notes,
                auditedAt: Self.nowIso()
            )
            continuation.yield(.modelDone(result))
            writeReport(result)
            return

        case (nil, .installIfMissing(let headroom)), (nil, .installAndUninstall(let headroom)):
            let freeGB = Self.freeDiskGB()
            let requiredGB = item.parsedDiskSizeGBForEstimator + headroom
            guard freeGB >= requiredGB else {
                let note = "no-disk-space (need \(Self.formatGB(requiredGB)) GB, have \(Self.formatGB(freeGB)) GB)"
                for auditCase in applicableCases {
                    caseResults[auditCase.id] = false
                    notes[auditCase.id] = note
                    continuation.yield(.caseResult(
                        modelName: item.displayName,
                        caseName: auditCase.id,
                        pass: false,
                        durationMs: 0,
                        note: note
                    ))
                }
                let result = ModelAuditResult(
                    modelID: item.id,
                    displayName: item.displayName,
                    verdict: .yellow("no-disk-space"),
                    caseResults: caseResults,
                    notes: notes,
                    auditedAt: Self.nowIso()
                )
                continuation.yield(.modelDone(result))
                writeReport(result)
                return
            }

            continuation.yield(.downloading(modelName: item.displayName, fraction: 0))
            do {
                model = try await downloader.preloadIfNeeded(item: auditItem, store: store) { fraction in
                    continuation.yield(.downloading(modelName: item.displayName, fraction: fraction))
                }
                if auditItem == item {
                    let installedModel = model
                    await MainActor.run {
                        store.upsertInstalledModel(installedModel)
                    }
                }
            } catch {
                let note = "download-failed: \(error.localizedDescription)"
                let result = ModelAuditResult(
                    modelID: item.id,
                    displayName: item.displayName,
                    verdict: .red(note),
                    caseResults: [:],
                    notes: [:],
                    auditedAt: Self.nowIso()
                )
                continuation.yield(.modelDone(result))
                writeReport(result)
                return
            }

            if case .installAndUninstall = policy {
                mustUninstall = true
            }
        }

        continuation.yield(.loading(modelName: item.displayName))
        var remainingCases = applicableCases[...]
        while let auditCase = remainingCases.popFirst() {
            continuation.yield(.caseStarted(modelName: item.displayName, caseName: auditCase.id))
            let (pass, durationMs, note) = await runCase(auditCase, model: model, resolved: resolved)
            caseResults[auditCase.id] = pass
            if let note {
                notes[auditCase.id] = note
            }
            continuation.yield(.caseResult(
                modelName: item.displayName,
                caseName: auditCase.id,
                pass: pass,
                durationMs: durationMs,
                note: note
            ))
            await RuntimeMemoryCoordinator.releaseAfterAudit(item.runtimeType)

            guard pass else {
                for skippedCase in remainingCases {
                    caseResults[skippedCase.id] = false
                    notes[skippedCase.id] = "skipped-after-failure"
                    continuation.yield(.caseResult(
                        modelName: item.displayName,
                        caseName: skippedCase.id,
                        pass: false,
                        durationMs: 0,
                        note: "skipped-after-failure"
                    ))
                }
                break
            }
        }

        let verdict: Verdict
        if let firstFailure = applicableCases.first(where: { caseResults[$0.id] == false }) {
            verdict = .red(firstFailure.id)
        } else {
            verdict = .green
        }

        let result = ModelAuditResult(
            modelID: item.id,
            displayName: item.displayName,
            verdict: verdict,
            caseResults: caseResults,
            notes: notes,
            auditedAt: Self.nowIso()
        )
        continuation.yield(.modelDone(result))
        writeReport(result)
        await RuntimeMemoryCoordinator.releaseAfterAudit(item.runtimeType)

        if mustUninstall {
            continuation.yield(.uninstalling(modelName: item.displayName))
            try? await downloader.remove(model, store: store)
            if auditItem == item {
                let catalogItem = model.catalogItem
                await MainActor.run {
                    store.removeInstalledModel(catalogItem)
                }
            }
        }
    }

    private func catalogItemForAudit(_ item: ModelCatalogItem) -> ModelCatalogItem {
        guard forceSourceVisionProbe,
              item.runtimeType == .mlx,
              item.sourceSupportsVision,
              !item.supportsVision
        else {
            return item
        }

        var inputModes = item.inputModes
        if !inputModes.contains(.image) {
            inputModes.append(.image)
        }

        return ModelCatalogItem(
            id: item.id,
            displayName: item.displayName,
            family: item.family,
            provider: item.provider,
            variant: item.variant,
            summary: item.summary,
            parameterSize: item.parameterSize,
            quantization: item.quantization,
            diskSize: item.diskSize,
            contextWindow: item.contextWindow,
            downloadURL: item.downloadURL,
            runtimeType: item.runtimeType,
            mlxModelID: item.mlxModelID,
            primaryUse: item.primaryUse,
            sourceSupportsVision: item.sourceSupportsVision,
            supportsVision: true,
            supportsReasoning: item.supportsReasoning,
            supportsToolCalling: item.supportsToolCalling,
            isThinkingModel: item.isThinkingModel,
            recommendedForIPhone: item.recommendedForIPhone,
            runtimeStatus: item.runtimeStatus,
            auditVerdict: item.auditVerdict,
            testedDeviceTier: item.testedDeviceTier,
            minimumTier: item.minimumTier,
            inputModes: inputModes
        )
    }

    private func resolvedModelForAudit(_ item: ModelCatalogItem) -> ResolvedModel {
        let resolved = ModelRuntimeResolver.resolve(catalog: item, store: profileStore)
        guard forceSourceVisionProbe,
              item.runtimeType == .mlx,
              item.sourceSupportsVision
        else {
            return resolved
        }

        return ResolvedModel(
            catalog: item,
            thinking: resolved.thinking,
            tools: resolved.tools,
            vision: .imageAndText,
            leakTokens: resolved.leakTokens,
            maxTokens: min(resolved.maxTokens, 128),
            verdict: resolved.verdict,
            isMismatch: true
        )
    }

    private func runCase(
        _ auditCase: AuditCase,
        model: InstalledModel,
        resolved: ResolvedModel
    ) async -> (pass: Bool, durationMs: Int, note: String?) {
        let start = Date()
        return await withTaskGroup(of: (pass: Bool, durationMs: Int, note: String?).self) { group in
            group.addTask {
                await self.runCaseBody(auditCase, model: model, resolved: resolved)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.caseTimeoutNanoseconds)
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                return (false, durationMs, "case-timeout")
            }

            guard let result = await group.next() else {
                return (false, 0, "case-timeout")
            }
            group.cancelAll()
            return result
        }
    }

    private func runCaseBody(
        _ auditCase: AuditCase,
        model: InstalledModel,
        resolved: ResolvedModel
    ) async -> (pass: Bool, durationMs: Int, note: String?) {
        let start = Date()
        let inference = inferenceFactory(model)
        let imageData = Self.imageData(named: auditCase.imageAssetName)
        let conversation = auditCase.id == "longConversation" ? Self.longConversationFixture() : []

        var text = ""
        var thinkingSeen = false
        var toolCallName: String?

        do {
            let (_, stream) = try await inference.generateStream(
                prompt: auditCase.prompt,
                model: model,
                conversation: conversation,
                searchContext: nil,
                systemPrompt: AppSettings.default.systemPrompt,
                imageData: imageData,
                settings: .default
            )

            eventLoop: for await event in stream {
                switch event {
                case .textDelta(let chunk):
                    text += chunk
                    if Self.shouldStopEarly(auditCase: auditCase, text: text) {
                        break eventLoop
                    }
                case .thinkingDelta:
                    thinkingSeen = true
                case .thinkingDone:
                    thinkingSeen = true
                case .toolCall(let name, _):
                    toolCallName = name
                case .done:
                    break
                }
            }
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            logger.error("Audit case \(auditCase.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return (false, durationMs, "error: \(error.localizedDescription)")
        }

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        let evaluation = evaluate(auditCase: auditCase, text: text, thinkingSeen: thinkingSeen, toolCallName: toolCallName, resolved: resolved)
        return (evaluation.pass, durationMs, evaluation.note)
    }

    private static func shouldStopEarly(auditCase: AuditCase, text: String) -> Bool {
        let normalized = text.lowercased()
        if !auditCase.expectations.containsAny.isEmpty,
           auditCase.expectations.containsAny.contains(where: { normalized.contains($0.lowercased()) }) {
            return true
        }
        if !auditCase.expectations.visionAnswerAcceptList.isEmpty,
           auditCase.expectations.visionAnswerAcceptList.contains(where: { normalized.contains($0.lowercased()) }) {
            return true
        }
        if auditCase.id == "leakStressor", normalized.contains("hello") {
            return true
        }
        return text.count >= maxAuditOutputCharacters
    }

    private func evaluate(
        auditCase: AuditCase,
        text: String,
        thinkingSeen: Bool,
        toolCallName: String?,
        resolved: ResolvedModel
    ) -> (pass: Bool, note: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if auditCase.expectations.nonEmpty && trimmed.isEmpty {
            return (false, "empty-output")
        }

        if auditCase.expectations.noLeakTokens {
            let leakPattern = #"(?i)(<\|im_end\|>|<\|endoftext\|>|<\|end_of_text\|>|<end_of_turn>|\[INST\]|<\|eot_id\|>|<\|channel>)"#
            if let regex = try? NSRegularExpression(pattern: leakPattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return (false, "leak-token-detected")
            }
        }

        if auditCase.expectations.thinkBlockDetected && !thinkingSeen {
            return (false, "missing-think-block")
        }

        if auditCase.expectations.toolCallFired && toolCallName != "web_search" {
            return (false, "tool-call-missing")
        }

        if !auditCase.expectations.visionAnswerAcceptList.isEmpty {
            let head = String(trimmed.prefix(100)).lowercased()
            guard auditCase.expectations.visionAnswerAcceptList.contains(where: { head.contains($0.lowercased()) }) else {
                return (false, "vision-answer-mismatch")
            }
        }

        if !auditCase.expectations.containsAny.isEmpty {
            let lowercased = trimmed.lowercased()
            guard auditCase.expectations.containsAny.contains(where: { lowercased.contains($0.lowercased()) }) else {
                return (false, "expected-text-missing")
            }
        }

        if auditCase.expectations.peakMemOK {
            let requiredGB = resolved.catalog.estimatedResidentGB(contextTokens: DeviceTier.current().safeContextTokens)
            if requiredGB > DeviceTier.current().jetsamSoftLimitGB {
                return (false, "memory-budget-risk")
            }
        }

        if auditCase.expectations.refusedUnsafeRequest && !ResponsibleAIGuard.isSafeRefusal(trimmed) {
            return (false, "rai-refusal-missing")
        }

        return (true, nil)
    }

    private func writeReport(_ result: ModelAuditResult) {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let directory = base
            .appending(path: "audits", directoryHint: .isDirectory)
            .appending(path: reportRunID, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "\(result.modelID.uuidString).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            try data.write(to: url)
        } catch {
            logger.error("Failed to write audit report: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func imageData(named name: String?) -> Data? {
        guard let name, let image = UIImage(named: name) else { return nil }
        return image.jpegData(compressionQuality: 0.85)
    }

    private static func nowIso() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func formatGB(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func freeDiskGB() -> Double {
        guard
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            let values = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let bytes = values.volumeAvailableCapacityForImportantUsage
        else {
            return 0
        }

        return Double(bytes) / (1024 * 1024 * 1024)
    }

    private static func longConversationFixture() -> [ChatMessage] {
        (1...36).flatMap { index -> [ChatMessage] in
            [
                ChatMessage(
                    role: .user,
                    text: "Planning note \(index): compare battery impact, model quality, privacy, and review readiness for this release."
                ),
                ChatMessage(
                    role: .assistant,
                    text: "Decision \(index): keep inference local by default, preserve reviewer access through Guest mode, and document any network use clearly."
                )
            ]
        }
    }
}

private extension InstalledModel {
    func withCatalogItem(_ item: ModelCatalogItem) -> InstalledModel {
        InstalledModel(
            id: id,
            catalogItem: item,
            installState: installState,
            progress: progress,
            installedAt: installedAt,
            localPath: localPath,
            isDefault: isDefault,
            statusMessage: statusMessage
        )
    }
}

#if DEBUG
extension ModelAuditRunner {
    func runCasePublic(
        _ auditCase: AuditCase,
        model: InstalledModel,
        resolved: ResolvedModel
    ) async -> (pass: Bool, durationMs: Int, note: String?) {
        await runCase(auditCase, model: model, resolved: resolved)
    }
}
#endif
