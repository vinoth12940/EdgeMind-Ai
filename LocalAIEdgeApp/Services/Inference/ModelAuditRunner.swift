import Foundation
import OSLog
import UIKit

actor ModelAuditRunner {
    private let inferenceFactory: (InstalledModel) -> any InferenceService
    private let downloader: AuditDownloader
    private let store: AppStateStore
    private let profileStore: RuntimeProfileStore
    private let reportRunID: String
    private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "ModelAuditRunner")

    init(
        inferenceFactory: @escaping (InstalledModel) -> any InferenceService,
        downloader: AuditDownloader,
        store: AppStateStore,
        profileStore: RuntimeProfileStore
    ) {
        self.inferenceFactory = inferenceFactory
        self.downloader = downloader
        self.store = store
        self.profileStore = profileStore
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
        let resolved = ModelRuntimeResolver.resolve(catalog: item, store: profileStore)
        let applicableCases = AuditCaseLibrary.standardCases.filter { $0.appliesWhen(resolved) }
        var caseResults: [String: Bool] = [:]
        var notes: [String: String] = [:]

        let existing = await downloader.installedModel(for: item, store: store)
        var model: InstalledModel
        var mustUninstall = false

        switch (existing, policy) {
        case (let installed?, _):
            model = installed

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
                model = try await downloader.preloadIfNeeded(item: item, store: store) { fraction in
                    continuation.yield(.downloading(modelName: item.displayName, fraction: fraction))
                }
                let installedModel = model
                await MainActor.run {
                    store.upsertInstalledModel(installedModel)
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
        for auditCase in applicableCases {
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
            let catalogItem = model.catalogItem
            await MainActor.run {
                store.removeInstalledModel(catalogItem)
            }
        }
    }

    private func runCase(
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

            for await event in stream {
                switch event {
                case .textDelta(let chunk):
                    text += chunk
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
