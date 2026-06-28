import Foundation
import Darwin

enum HeadlessModelAuditLauncher {
    private static let runArgument = "--localai-run-model-audit"
    private static let allRuntimesArgument = "--localai-audit-all-runtimes"
    private static let requireInstalledArgument = "--localai-audit-require-installed"
    private static let uninstallAfterArgument = "--localai-audit-uninstall-after"
    private static let visionOnlyArgument = "--localai-audit-vision-only"
    private static let sourceVisionProbeArgument = "--localai-audit-source-vision"
    private static let ignoreTierArgument = "--localai-audit-ignore-tier"
    private static let modelFilterArgument = "--localai-audit-model"
    private static let caseTimeoutArgument = "--localai-audit-case-timeout-sec"

    @MainActor
    static func runIfRequested(store: AppStateStore) async {
        let arguments = CommandLine.arguments
        guard arguments.contains(runArgument) else { return }

        let currentTier = DeviceTier.current()
        let includeAllRuntimes = arguments.contains(allRuntimesArgument)
        let sourceVisionProbe = arguments.contains(sourceVisionProbeArgument)
        let ignoreTier = arguments.contains(ignoreTierArgument)
        let policy: InstallPolicy
        if arguments.contains(requireInstalledArgument) {
            policy = .requireInstalled
        } else if arguments.contains(uninstallAfterArgument) {
            policy = .installAndUninstall(diskHeadroomGB: 2.0)
        } else {
            policy = .installIfMissing(diskHeadroomGB: 2.0)
        }

        var items = store.catalog
            .filter { $0.primaryUse == .chat }

        if !ignoreTier {
            items = items.filter { $0.minimumTier <= currentTier }
        }

        if !includeAllRuntimes {
            items = items.filter { $0.runtimeType == .mlx || $0.runtimeType == .liteRTLM }
        }
        if arguments.contains(visionOnlyArgument) {
            items = items.filter { sourceVisionProbe ? $0.sourceSupportsVision : $0.supportsVision }
        }
        if let modelFilter = argumentValue(after: modelFilterArgument, in: arguments) {
            let normalized = modelFilter.lowercased()
            items = items.filter { item in
                item.id.uuidString.lowercased() == normalized
                    || item.displayName.lowercased().contains(normalized)
                    || item.mlxModelID?.lowercased() == normalized
            }
        }

        print("[MODEL_AUDIT] START tier=\(currentTier.displayName) models=\(items.count) policy=\(policy.logLabel) runtimes=\(includeAllRuntimes ? "all" : "mlx+litert") visionOnly=\(arguments.contains(visionOnlyArgument)) sourceVisionProbe=\(sourceVisionProbe) ignoreTier=\(ignoreTier)")
        for item in items {
            print("[MODEL_AUDIT] QUEUED \(item.displayName) runtime=\(item.runtimeType.rawValue) size=\(item.diskSize)")
        }

        let auditCases = arguments.contains(visionOnlyArgument)
            ? AuditCaseLibrary.standardCases.filter { $0.imageAssetName != nil }
            : AuditCaseLibrary.standardCases

        let runner = ModelAuditRunner(
            inferenceFactory: { installed in
                if installed.catalogItem.runtimeType == .foundationModels {
                    return AppleFoundationInferenceService()
                }
                if installed.catalogItem.runtimeType == .mlx {
                    return MLXInferenceService()
                }
                if installed.catalogItem.runtimeType == .liteRTLM {
                    return LiteRTInferenceService()
                }
                return LocalLlamaInferenceService()
            },
            downloader: DefaultAuditDownloader(),
            store: store,
            profileStore: RuntimeProfileStore(),
            auditCases: auditCases,
            forceSourceVisionProbe: sourceVisionProbe,
            caseTimeoutNanoseconds: caseTimeoutNanoseconds(from: arguments)
        )

        var lastDownloadPercentByModel: [String: Int] = [:]
        for await progress in await runner.auditCatalog(items: items, policy: policy) {
            if case .downloading(let modelName, let fraction) = progress {
                let percent = Int(fraction * 100)
                let lastPercent = lastDownloadPercentByModel[modelName]
                guard lastPercent == nil || percent > (lastPercent ?? 0) || percent == 100 else {
                    continue
                }
                lastDownloadPercentByModel[modelName] = percent
            }
            print("[MODEL_AUDIT] \(progress.logLine)")
        }

        print("[MODEL_AUDIT] FINISHED")
        fflush(nil)
        _exit(0)
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func caseTimeoutNanoseconds(from arguments: [String]) -> UInt64 {
        guard let raw = argumentValue(after: caseTimeoutArgument, in: arguments),
              let seconds = Double(raw),
              seconds > 0
        else {
            return ModelAuditRunner.defaultCaseTimeoutNanoseconds
        }
        return UInt64(seconds * 1_000_000_000)
    }
}

private extension InstallPolicy {
    var logLabel: String {
        switch self {
        case .requireInstalled:
            return "requireInstalled"
        case .installIfMissing:
            return "installIfMissing"
        case .installAndUninstall:
            return "installAndUninstall"
        }
    }
}

private extension AuditProgress {
    var logLine: String {
        switch self {
        case .downloading(let modelName, let fraction):
            return "DOWNLOADING model=\"\(modelName)\" progress=\(Int(fraction * 100))%"
        case .loading(let modelName):
            return "LOADING model=\"\(modelName)\""
        case .caseStarted(let modelName, let caseName):
            return "CASE_START model=\"\(modelName)\" case=\"\(caseName)\""
        case .caseResult(let modelName, let caseName, let pass, let durationMs, let note):
            return "CASE_RESULT model=\"\(modelName)\" case=\"\(caseName)\" pass=\(pass) durationMs=\(durationMs) note=\"\(note ?? "")\""
        case .modelDone(let result):
            return "MODEL_DONE model=\"\(result.displayName)\" verdict=\"\(result.verdict.logLabel)\""
        case .uninstalling(let modelName):
            return "UNINSTALLING model=\"\(modelName)\""
        case .runFinished:
            return "RUN_FINISHED"
        }
    }
}

private extension Verdict {
    var logLabel: String {
        switch self {
        case .green:
            return "green"
        case .yellow(let reason):
            return "yellow:\(reason)"
        case .red(let reason):
            return "red:\(reason)"
        }
    }
}
