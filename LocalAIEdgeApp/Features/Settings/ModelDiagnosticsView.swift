import SwiftUI

struct ModelDiagnosticsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var isRunning = false
    @State private var statusLine = "Idle"
    @State private var results: [ModelAuditResult] = []

    var body: some View {
        ZStack {
            AppBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    runControls
                    readinessChecklist
                    resultsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 44)
            }
        }
        .navigationTitle("Model Diagnostics")
        .navigationBarTitleDisplayMode(.inline)

    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Audit Lab")
                .font(.appDisplay(26))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Validate on-device runtime behavior, leak protection, tool calls, and vision expectations for the current hardware tier.")
                .font(.appBody(13))
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 10) {
                overviewPill(label: "Tier", value: DeviceTier.current().displayName, color: AppTheme.accent)
                overviewPill(label: "Installed", value: "\(store.installedModels.filter { $0.installState == .installed }.count)", color: AppTheme.success)
                overviewPill(label: "Status", value: statusLine, color: isRunning ? AppTheme.warning : AppTheme.textSecondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surfaceGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
        )
    }

    private var runControls: some View {
        HStack(spacing: 10) {
            Button(isRunning ? "Running..." : "Run Full Audit") {
                Task { await runAll() }
            }
            .disabled(isRunning)
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isRunning
                            ? AnyShapeStyle(AppTheme.warning.opacity(0.26))
                            : AnyShapeStyle(AppTheme.accentGradient)
                    )
            )
            .foregroundStyle(isRunning ? AppTheme.warning : AppTheme.background)
            .font(.appCaps(13))

            Text("Policy: Install If Missing")
                .font(.appBody(12))
                .foregroundStyle(AppTheme.textTertiary)

            Spacer()
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest Results")
                .font(.appDisplay(19))
                .foregroundStyle(AppTheme.textPrimary)

            if results.isEmpty {
                Text("No diagnostics runs yet.")
                    .font(.appBody(13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.panelRaised.opacity(0.82))
                    )
            } else {
                ForEach(results) { result in
                    NavigationLink {
                        AuditResultDetailView(result: result)
                    } label: {
                        HStack(spacing: 12) {
                            verdictBadge(result.verdict)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.displayName)
                                    .font(.appBody(15))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(result.auditedAt)
                                    .font(.appBody(11))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.surfaceGradient)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var readinessChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App Review Readiness")
                .font(.appDisplay(19))
                .foregroundStyle(AppTheme.textPrimary)

            diagnosticRow(icon: "photo.on.rectangle", title: "Vision probe", value: "Runs for MLX VLM models only", color: AppTheme.accent)
            diagnosticRow(icon: "doc.text.magnifyingglass", title: "Document probe", value: "Text/PDF/CSV context included", color: AppTheme.success)
            diagnosticRow(icon: "waveform", title: "Voice mode", value: store.settings.voiceModeEnabled ? "Enabled" : "Available in Settings", color: store.settings.voiceModeEnabled ? AppTheme.success : AppTheme.warning)
            diagnosticRow(icon: "sparkles", title: "Shortcuts", value: "Ask, Diagnostics, Voice, Models intents installed", color: AppTheme.accent)
            diagnosticRow(icon: "memorychip", title: "Idle unload", value: "Chat releases runtimes after 90 seconds idle", color: AppTheme.success)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.panelRaised.opacity(0.82))
        )
    }

    private func diagnosticRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appBody(13))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(value)
                    .font(.appBody(11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
        }
    }

    private func overviewPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.appCaps(9))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.appBody(12))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        statusLine = "Preparing"

        let runner = ModelAuditRunner(
            inferenceFactory: { installed in
                let service: any InferenceService
                if installed.catalogItem.runtimeType == .foundationModels {
                    service = AppleFoundationInferenceService()
                } else if installed.catalogItem.runtimeType == .mlx {
                    service = MLXInferenceService()
                } else {
                    service = LocalLlamaInferenceService()
                }
                return service
            },
            downloader: DefaultAuditDownloader(),
            store: store,
            profileStore: RuntimeProfileStore()
        )

        let currentTier = DeviceTier.current()
        let items = store.catalog
            .filter { $0.runtimeType == .mlx }
            .filter { $0.minimumTier <= currentTier }

        var newResults: [ModelAuditResult] = []
        for await progress in await runner.auditCatalog(items: items, policy: InstallPolicy.installIfMissing(diskHeadroomGB: 2.0)) {
            switch progress {
            case .downloading(let modelName, let fraction):
                statusLine = "Downloading \(modelName) \(Int(fraction * 100))%"
            case .loading(let modelName):
                statusLine = "Loading \(modelName)"
            case .caseStarted(let modelName, let caseName):
                statusLine = "Running \(modelName): \(caseName)"
            case .caseResult:
                break
            case .modelDone(let result):
                newResults.append(result)
            case .uninstalling(let modelName):
                statusLine = "Uninstalling \(modelName)"
            case .runFinished:
                statusLine = "Finished"
            }
        }

        results = newResults.sorted { $0.displayName < $1.displayName }
        isRunning = false
    }

    @ViewBuilder
    private func verdictBadge(_ verdict: Verdict) -> some View {
        switch verdict {
        case .green:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .yellow:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
        case .red:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

private struct AuditResultDetailView: View {
    let result: ModelAuditResult

    var body: some View {
        List {
            Section("Verdict") {
                Text(verdictText(result.verdict))
            }

            Section("Cases") {
                ForEach(result.caseResults.keys.sorted(), id: \.self) { key in
                    HStack {
                        Image(systemName: result.caseResults[key] == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.caseResults[key] == true ? .green : .red)
                        Text(key)
                        Spacer()
                        if let note = result.notes[key], !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                ShareLink(item: exportURL(for: result)) {
                    Label("Export report", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(result.displayName)
        .navigationBarTitleDisplayMode(.inline)

    }

    private func verdictText(_ verdict: Verdict) -> String {
        switch verdict {
        case .green:
            return "green"
        case .yellow(let note):
            return "yellow: \(note)"
        case .red(let note):
            return "red: \(note)"
        }
    }

    private func exportURL(for result: ModelAuditResult) -> URL {
        let data = (try? JSONEncoder().encode(result)) ?? Data()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(result.displayName)-audit.json")
        try? data.write(to: url)
        return url
    }
}
