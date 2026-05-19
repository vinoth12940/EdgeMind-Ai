import SwiftUI
import OSLog

private let chatLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "ChatView")

struct ChatView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.selectedTab) private var selectedTab
    @State private var prompt = ""
    @State private var liveSearchEnabled = false
    @State private var searchAutoInitialized = false
    @State private var isInputFocused = false
    @State private var isSending = false
    @State private var generationTask: Task<Void, Never>?
    @State private var activeGenerationID: UUID?
    @State private var inferenceService: InferenceService = LocalLlamaInferenceService()
    @State private var mlxInferenceService: InferenceService = MLXInferenceService()
    @State private var appleFoundationInferenceService: InferenceService = AppleFoundationInferenceService()
    @State private var showModelPicker = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var attachedImage: UIImage?
    @State private var attachedDocuments: [ChatAttachment] = []
    @State private var idleRuntimeReleaseTask: Task<Void, Never>?
    @StateObject private var voiceController = VoiceInteractionController()

    private let profileStore = RuntimeProfileStore()

    private func resolved(for model: InstalledModel) -> ResolvedModel {
        ModelRuntimeResolver.resolve(catalog: model.catalogItem, store: profileStore)
    }

    private let streamUpdateInterval: Duration = .milliseconds(80)

    /// Tool definition injected into system prompt when the search toggle is ON
    /// so any model can decide whether to search via <tool_call>.
    private static let toolCallDefinition = """

# Tools

You have access to the following tool. Call it when you need current or real-time information (news, scores, weather, prices, recent events).

## web_search
Search the web for up-to-date information.
Parameters: query (string) — the search query

To call it, output ONLY this block (no other text before the closing tag):
<tool_call>
{"name": "web_search", "arguments": {"query": "your search query here"}}
</tool_call>

Rules:
- Call it for anything requiring real-time, current, or recent information.
- If a follow-up question asks for more detail about a topic you previously searched, call web_search AGAIN with a refined query.
- Do NOT refuse to search. If in doubt, search.
- Call it at most once per response.
"""

    private var composerBottomSpacing: CGFloat {
        isInputFocused ? 4 : 8
    }

    private var isVisionModel: Bool {
        guard let model = store.defaultModel else { return false }
        // Runtime profile is the gate here. Source/model-card vision claims are
        // not enough to keep image attachments enabled after a red device audit.
        return resolved(for: model).vision == .imageAndText
    }

    private var activeModel: InstalledModel? {
        store.defaultModel
    }

    private var searchGatewayConfigured: Bool {
        SearchGatewayFactory.make(settings: store.settings) != nil
    }

    private var searchStatusLabel: String {
        if liveSearchEnabled && searchGatewayConfigured {
            return "Live Search"
        }
        if searchGatewayConfigured {
            return "Search Ready"
        }
        return "Local Only"
    }

    private var searchStatusColor: Color {
        if liveSearchEnabled && searchGatewayConfigured {
            return AppTheme.warning
        }
        if searchGatewayConfigured {
            return AppTheme.accent
        }
        return AppTheme.success
    }

    private var runtimeNotice: String? {
        guard let model = activeModel else { return nil }

        if model.catalogItem.family == .gemma && model.catalogItem.runtimeType == .gguf {
            return "Gemma 4 is running through llama.cpp GGUF in text-only mode. Image input is disabled on this runtime path."
        }

        if model.catalogItem.runtimeType == .gguf && model.catalogItem.supportsVision == false {
            return "This model is running locally through llama.cpp. Text chat is supported on this runtime path."
        }

        if model.catalogItem.runtimeType == .foundationModels {
            return AppleFoundationModelService.availabilityMessage ?? "This model uses Apple's system Foundation Models runtime. The app does not download or own these weights."
        }

        return nil
    }

    private func memoryGuardMessage(for model: InstalledModel) -> String? {
        let tier = DeviceTier.current()
        // If the current device tier meets or exceeds the model's minimum tier requirement,
        // do not block execution with the memory guard.
        guard tier < model.catalogItem.minimumTier else { return nil }

        let estimatedGB = model.catalogItem.estimatedResidentGB(contextTokens: tier.safeContextTokens)
        guard estimatedGB > tier.jetsamSoftLimitGB else { return nil }

        return "\(model.catalogItem.displayName) is above the safe memory budget for this device tier (\(String(format: "%.1f", estimatedGB)) GB estimated vs \(String(format: "%.1f", tier.jetsamSoftLimitGB)) GB safe). Pick a smaller model to avoid an iOS memory kill."
    }

    private var lastAssistantResponseText: String? {
        activeMessages
            .last(where: { $0.role == .assistant })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferenceServiceForModel(_ model: InstalledModel) -> InferenceService {
        switch model.catalogItem.runtimeType {
        case .gguf:
            return inferenceService
        case .mlx:
            return mlxInferenceService
        case .foundationModels:
            return appleFoundationInferenceService
        }
    }

    var body: some View {
        ZStack {
            AppBackdropView()

            VStack(spacing: 0) {
                compactTopBar

                if activeMessages.isEmpty {
                    ScrollView {
                        emptyState
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .scale(scale: 1.1).combined(with: .opacity)
                                )
                            )
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                                LazyVStack(spacing: 18) {
                                    Color.clear
                                        .frame(height: 4)

                                ForEach(activeMessages) { message in
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }

                                if isSending {
                                    generationStatusCard
                                    .id("typing")
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .defaultScrollAnchor(.bottom)
                        .onAppear { scrollProxy = proxy }
                        .onChange(of: activeMessages.count) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(activeMessages.last?.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: isSending) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                if isSending {
                                    proxy.scrollTo("typing", anchor: .bottom)
                                } else {
                                    proxy.scrollTo(activeMessages.last?.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .floatingDockHidden()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposerView(
                prompt: $prompt,
                liveSearchEnabled: $liveSearchEnabled,
                attachedImage: $attachedImage,
                attachedDocuments: $attachedDocuments,
                isInputFocused: $isInputFocused,
                voiceModeEnabled: store.settings.voiceModeEnabled,
                isListening: voiceController.isListening,
                voiceStatusMessage: voiceController.lastError,
                isVisionModel: isVisionModel,
                isSending: isSending,
                isSearchConfigured: searchGatewayConfigured,
                onSend: sendPrompt,
                onToggleVoiceInput: toggleVoiceInput,
                onStop: stopGeneration
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, composerBottomSpacing)
            .background(
                LinearGradient(
                    colors: [Color.clear, AppTheme.background.opacity(0.72), AppTheme.background.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .onAppear {
            store.reconcileInstalledFiles()
            applyIntentHandoff()
            // Auto-enable search when a provider is configured.
            // The user can still toggle it OFF per-chat via the composer "+" menu.
            if !searchAutoInitialized {
                searchAutoInitialized = true
                if SearchGatewayFactory.shouldAutoEnableLiveSearch(settings: store.settings) {
                    liveSearchEnabled = true
                }
            }
        }
        .onChange(of: voiceController.transcript) {
            if voiceController.isListening {
                prompt = voiceController.transcript
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            applyIntentHandoff()
        }
        .onChange(of: store.settings.voiceModeEnabled) {
            if !store.settings.voiceModeEnabled {
                voiceController.stopListening()
                voiceController.stopSpeaking()
            }
        }
        .onChange(of: store.defaultModel?.id) {
            // If user switches to a text-only model, drop pending image attachment
            // so we don't accidentally route image data into a non-vision runtime.
            if !isVisionModel {
                attachedImage = nil
            }
        }
        .onDisappear {
            idleRuntimeReleaseTask?.cancel()
            idleRuntimeReleaseTask = nil
        }
    }

    private var activeMessages: [ChatMessage] {
        store.selectedSession?.messages ?? []
    }

    private func applyIntentHandoff() {
        if let pendingPrompt = LocalAIIntentHandoffStore.consumePendingPrompt() {
            prompt = pendingPrompt
            isInputFocused = true
        }

        if LocalAIIntentHandoffStore.consumeVoiceRequest(), store.settings.voiceModeEnabled {
            Task {
                await voiceController.toggleListening(seedText: prompt)
            }
        }
    }

    private var compactTopBar: some View {
        HStack(spacing: 10) {
            Button {
                showModelPicker = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(searchStatusColor)
                        .frame(width: 6, height: 6)
                    Text(activeModel?.catalogItem.displayName ?? "Select Model")
                        .font(.appCaps(12))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.panelRaised.opacity(0.82))
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Menu {
                Button {
                    isInputFocused = false
                    store.createSession(using: store.defaultModel?.catalogItem.id)
                } label: {
                    Label("New Chat", systemImage: "plus")
                }

                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab.wrappedValue = 1
                    }
                } label: {
                    Label("Models", systemImage: "square.stack.3d.up")
                }

                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab.wrappedValue = 2
                    }
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab.wrappedValue = 3
                    }
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.panelRaised.opacity(0.9))
                        .frame(width: 34, height: 34)
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .accessibilityLabel("Open menu")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var sessionOverviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                sessionMetricCard(
                    title: "Runtime",
                    value: activeModel?.catalogItem.runtimeType.label ?? "No runtime",
                    detail: activeModel?.catalogItem.parameterSize ?? "Install a model",
                    color: activeModel?.catalogItem.runtimeType == .mlx ? AppTheme.accent : AppTheme.warning
                )
                sessionMetricCard(
                    title: "Context",
                    value: activeModel?.catalogItem.contextWindow ?? "None",
                    detail: "Model window",
                    color: AppTheme.warning
                )
                sessionMetricCard(
                    title: "Search",
                    value: searchStatusLabel,
                    detail: liveSearchEnabled ? "Web grounded" : (searchGatewayConfigured ? "Ready to arm" : "Offline only"),
                    color: searchStatusColor
                )
                sessionMetricCard(
                    title: "Voice",
                    value: store.settings.voiceModeEnabled ? "Enabled" : "Muted",
                    detail: store.settings.voiceModeEnabled ? "Dictation + playback" : "Text first",
                    color: store.settings.voiceModeEnabled ? AppTheme.accentSoft : AppTheme.textSecondary
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var generationStatusCard: some View {
        HStack {
            HStack(spacing: 12) {
                TypingIndicator()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Generating response")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Local runtime is working…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.surfaceGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.26), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )

            Spacer(minLength: 44)
        }
    }

    private struct PromptStarter: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let prompt: String
    }

    private var promptStarters: [PromptStarter] {
        [
            PromptStarter(
                title: "Organize",
                subtitle: "Notes into plans",
                icon: "rectangle.grid.1x2",
                prompt: "Organize these ideas into a clear action plan with priorities and next steps."
            ),
            PromptStarter(
                title: "Summarize",
                subtitle: "Compress text fast",
                icon: "text.alignleft",
                prompt: "Summarize this clearly in five bullet points and call out the most important detail."
            ),
            PromptStarter(
                title: "Improve",
                subtitle: "Sharpen a draft",
                icon: "sparkles",
                prompt: "Rewrite this to be sharper, clearer, and more confident without losing the meaning."
            )
        ]
    }

    private func primePrompt(_ starter: PromptStarter) {
        prompt = starter.prompt
        isInputFocused = true
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(searchStatusColor)
                                .frame(width: 7, height: 7)
                            Text(searchStatusLabel.uppercased())
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(searchStatusColor)
                                .tracking(1.0)
                        }

                        Button {
                            showModelPicker = true
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(activeModel?.catalogItem.displayName ?? "Select Model")
                                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(2)

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }

                                Text(activeModel?.catalogItem.family.lab ?? "Install a local model to start")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)

                        Text(store.selectedSession?.title ?? "Fresh local conversation")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 10) {
                        Button {
                            isInputFocused = false
                            store.createSession(using: store.defaultModel?.catalogItem.id)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppTheme.background)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(AppTheme.accentGradient))
                        }
                        .accessibilityLabel("Start new chat")

                        HStack(spacing: 4) {
                            headerRailButton(icon: "square.stack.3d.up", accessibilityLabel: "Models") {
                                isInputFocused = false
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                    selectedTab.wrappedValue = 1
                                }
                            }
                            headerRailButton(icon: "clock.arrow.circlepath", accessibilityLabel: "History") {
                                isInputFocused = false
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                    selectedTab.wrappedValue = 2
                                }
                            }
                            headerRailButton(icon: "slider.horizontal.3", accessibilityLabel: "Settings") {
                                isInputFocused = false
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                    selectedTab.wrappedValue = 3
                                }
                            }
                        }
                        .padding(4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.panelRaised.opacity(0.72))
                        )
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let model = activeModel {
                            headerChip(label: model.catalogItem.parameterSize, tone: .neutral)
                            headerChip(label: model.catalogItem.contextWindow, tone: .neutral)
                            headerChip(label: model.catalogItem.runtimeType.label, tone: model.catalogItem.runtimeType == .mlx ? .accent : .neutral)
                            headerChip(label: model.catalogItem.supportsVision ? "Vision" : "Text", tone: model.catalogItem.supportsVision ? .accent : .neutral)

                            if model.catalogItem.supportsToolCalling {
                                headerChip(label: "Tools", tone: .warning)
                            }
                            if model.catalogItem.supportsReasoning || model.catalogItem.isThinkingModel {
                                headerChip(label: "Reasoning", tone: .accent)
                            }
                        } else {
                            headerChip(label: "No model", tone: .warning)
                        }

                        if searchGatewayConfigured {
                            headerChip(label: liveSearchEnabled ? "Live Search On" : "Search Ready", tone: .warning)
                        }

                        if store.settings.voiceModeEnabled,
                           let lastAssistantResponseText,
                           !lastAssistantResponseText.isEmpty {
                            Button {
                                replayLastAssistantResponse()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: voiceController.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(voiceController.isSpeaking ? "Stop" : "Replay")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(voiceController.isSpeaking ? AppTheme.warning : AppTheme.accentSoft)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            if let runtimeNotice {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.warning)
                        .padding(.top, 1)

                    Text(runtimeNotice)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.surfaceGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.heroGradient)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func headerRailButton(icon: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.04)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private enum HeaderChipTone {
        case neutral
        case accent
        case warning
    }

    private func headerChip(label: String, tone: HeaderChipTone) -> some View {
        let fill: Color
        let foreground: Color

        switch tone {
        case .neutral:
            fill = Color.white.opacity(0.06)
            foreground = AppTheme.textTertiary
        case .accent:
            fill = AppTheme.accent.opacity(0.10)
            foreground = AppTheme.accent.opacity(0.85)
        case .warning:
            fill = AppTheme.warning.opacity(0.10)
            foreground = AppTheme.warning.opacity(0.85)
        }

        return Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.3)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(fill)
            .clipShape(Capsule())
    }

    private func sessionMetricCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(width: 142, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.panelRaised.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 0.7)
        )
    }

    // MARK: - Model Picker Sheet

    private var modelPickerSheet: some View {
        let chatCatalog = store.catalog.filter { $0.primaryUse == .chat }
        let installedItems = chatCatalog.filter { item in
            store.installedModels.contains(where: { $0.catalogItem.id == item.id && $0.installState == .installed })
        }
        let availableItems = chatCatalog.filter { item in
            !store.installedModels.contains(where: { $0.catalogItem.id == item.id && $0.installState == .installed })
        }

        return NavigationStack {
            List {
                if !installedItems.isEmpty {
                    Section {
                        ForEach(installedItems, id: \.id) { item in
                            modelPickerRow(item: item, isInstalled: true)
                        }
                    } header: {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.success)
                            .textCase(nil)
                    }
                }

                if !availableItems.isEmpty {
                    Section {
                        ForEach(availableItems, id: \.id) { item in
                            modelPickerRow(item: item, isInstalled: false)
                        }
                    } header: {
                        Label("Available to Download", systemImage: "arrow.down.circle")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.textTertiary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showModelPicker = false
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    private func modelPickerRow(item: ModelCatalogItem, isInstalled: Bool) -> some View {
        let isSelected = store.defaultModel?.catalogItem.id == item.id
        return HStack(spacing: 12) {
            Image(systemName: item.runtimeType.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(isSelected ? AppTheme.accent.opacity(0.15) : AppTheme.accent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isInstalled ? AppTheme.textPrimary : AppTheme.textTertiary)

                HStack(spacing: 6) {
                    Text(item.parameterSize)
                    Text("\u{2022}")
                    Text(item.runtimeType.label)
                    Text("\u{2022}")
                    Text(item.diskSize)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.accent)
            } else if !isInstalled {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isInstalled {
                store.setDefaultModel(id: item.id)
                showModelPicker = false
            } else {
                showModelPicker = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    selectedTab.wrappedValue = 1
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(activeModel == nil ? "Start from a private local canvas" : "Shape the first turn with \(activeModel?.catalogItem.displayName ?? "your model")")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(activeModel?.catalogItem.summary ?? "Install a model from the library to start writing, summarizing, and reasoning entirely on-device.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
            }

            if let model = activeModel {
                HStack(spacing: 6) {
                    emptyStateMetaPill(label: model.catalogItem.parameterSize)
                    emptyStateMetaPill(label: model.catalogItem.runtimeType.label)
                    emptyStateMetaPill(label: model.catalogItem.supportsVision ? "Image ready" : "Text only")
                }
            }

            HStack(spacing: 10) {
                emptyStateFeature(icon: "lock.shield.fill", title: "Local by default", detail: "Your prompt, model, and history stay on this device.", color: AppTheme.success)
                emptyStateFeature(icon: "globe", title: searchGatewayConfigured ? "Search lane ready" : "Offline lane", detail: searchGatewayConfigured ? "Turn on live grounding when you need current results." : "Add Serper or a gateway in Settings.", color: searchStatusColor)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(promptStarters) { starter in
                    Button {
                        primePrompt(starter)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: starter.icon)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text(starter.title)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(starter.subtitle)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(AppTheme.panelRaised.opacity(0.88))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.defaultModel == nil {
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab.wrappedValue = 1
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Browse Models")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.accentGradient)
                    )
                    .shadow(color: AppTheme.accent.opacity(0.25), radius: 16, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.surfaceGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
    }

    private func emptyStateMetaPill(label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule(style: .continuous))
    }

    private func emptyStateFeature(icon: String, title: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.panelRaised.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        isSending = false
        scheduleIdleRuntimeRelease()
    }

    private func toggleVoiceInput() {
        guard store.settings.voiceModeEnabled else { return }

        Task {
            await voiceController.toggleListening(seedText: prompt)
        }
    }

    private func replayLastAssistantResponse() {
        if voiceController.isSpeaking {
            voiceController.stopSpeaking()
            return
        }

        guard let lastAssistantResponseText, !lastAssistantResponseText.isEmpty else { return }
        voiceController.speak(lastAssistantResponseText, using: store.settings)
    }

    /// Extract a web_search tool call from raw text (handles both standard and Gemma 4 formats).
    /// Used as a fallback when StreamProcessor misses <tool_call> due to tag splitting across tokens.
    private static func extractToolCallQuery(from text: String) -> String? {
        // Try standard <tool_call>...</tool_call>
        if let openRange = text.range(of: "<tool_call>", options: .caseInsensitive),
           let closeRange = text.range(of: "</tool_call>", options: .caseInsensitive, range: openRange.upperBound..<text.endIndex) {
            return parseWebSearchQuery(String(text[openRange.upperBound..<closeRange.lowerBound]))
        }
        // Try Gemma 4 native <|tool_call>...<tool_call|>
        if let openRange = text.range(of: "<|tool_call>", options: .caseInsensitive),
           let closeRange = text.range(of: "<tool_call|>", options: .caseInsensitive, range: openRange.upperBound..<text.endIndex) {
            return parseWebSearchQuery(String(text[openRange.upperBound..<closeRange.lowerBound]))
        }
        return nil
    }

    private static func parseWebSearchQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Try to find JSON object in the text (handles models that add extra text before JSON)
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let data = String(trimmed[jsonStart...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Name check (case-insensitive) — allow "web_search", "search", etc.
        if let name = json["name"] as? String,
           !name.lowercased().contains("search") { return nil }

        // Try nested dict arguments first
        if let args = json["arguments"] as? [String: Any],
           let q = args["query"] as? String, !q.isEmpty { return q }
        // Try string-encoded arguments
        if let argsStr = json["arguments"] as? String,
           let argsData = argsStr.data(using: .utf8),
           let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
           let q = argsDict["query"] as? String, !q.isEmpty { return q }
        // Try flat query key
        if let q = json["query"] as? String, !q.isEmpty { return q }
        return nil
    }

    private func cleanedDisplayedAssistantText(_ text: String) -> String {
        var cleaned = AssistantResponseSanitizer.clean(text)
        cleaned = cleaned.replacingOccurrences(of: AssistantResponseFallback.emptyOutput, with: "")
        cleaned = cleaned.replacingOccurrences(of: AssistantResponseFallback.emptyOutputAfterThinking, with: "")
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedAssistantText(from rawText: String, prompt: String, thinkingSeen: Bool) -> String {
        let finalText = cleanedDisplayedAssistantText(rawText)
        if AssistantResponseFallback.isInstructionEcho(finalText, systemPrompt: store.settings.systemPrompt) {
            return AssistantResponseFallback.instructionEcho
        }
        if finalText.isEmpty || AssistantResponseFallback.isPromptEcho(finalText, prompt: prompt) {
            return AssistantResponseFallback.emptyOutputMessage(thinkingSeen: thinkingSeen)
        }
        return finalText
    }

    private func searchAwareAssistantText(
        from rawText: String,
        prompt: String,
        thinkingSeen: Bool,
        searchContext: SearchContext?
    ) -> String {
        let resolved = resolvedAssistantText(from: rawText, prompt: prompt, thinkingSeen: thinkingSeen)
        guard let searchContext else { return resolved }
        guard SearchResultFallbackComposer.shouldReplace(resolved, prompt: prompt, searchContext: searchContext) else {
            return resolved
        }
        return SearchResultFallbackComposer.compose(query: prompt, searchContext: searchContext)
    }

    private func encodedAttachmentData(from image: UIImage?) -> Data? {
        guard let image else { return nil }

        let maxBytes = 700_000
        let qualitySteps: [CGFloat] = [0.75, 0.65, 0.55, 0.45, 0.35, 0.25]
        for quality in qualitySteps {
            guard let data = image.jpegData(compressionQuality: quality) else { continue }
            if data.count <= maxBytes {
                return data
            }
        }
        return image.jpegData(compressionQuality: 0.25)
    }

    @MainActor
    private func scheduleIdleRuntimeRelease() {
        idleRuntimeReleaseTask?.cancel()
        idleRuntimeReleaseTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            if Task.isCancelled { return }
            await RuntimeMemoryCoordinator.releaseAll()
        }
    }

    @MainActor
    private func updateStreamingMessage(_ text: String, messageID: UUID, sessionID: UUID, persist: Bool = false) {
        store.updateMessageText(messageID, in: sessionID, text: text, persist: persist)
    }

    @MainActor
    private func finishGenerationIfCurrent(_ taskID: UUID) {
        guard activeGenerationID == taskID else { return }
        isSending = false
        generationTask = nil
        activeGenerationID = nil
        scheduleIdleRuntimeRelease()
    }

    private func sendPrompt() {
        guard !isSending else { return }
        voiceController.stopListening()

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentImage = attachedImage
        let currentDocuments = attachedDocuments
        guard !trimmedPrompt.isEmpty || currentImage != nil || !currentDocuments.isEmpty else { return }
        if store.selectedSession == nil {
            store.createSession(using: store.defaultModel?.catalogItem.id)
        }
        guard let sessionID = store.selectedSession?.id else { return }
        guard let model = store.defaultModel else {
            store.appendMessage(
                ChatMessage(role: .assistant, text: InferenceServiceError.noModelInstalled.localizedDescription),
                to: sessionID
            )
            return
        }

        if let memoryGuardMessage = memoryGuardMessage(for: model) {
            store.appendMessage(ChatMessage(role: .assistant, text: memoryGuardMessage), to: sessionID)
            return
        }

        // Encode image at bounded size to avoid memory spikes during persistence/inference.
        let jpegData = encodedAttachmentData(from: currentImage)
        let attachments = ([jpegData.map { ChatAttachment.image($0) }].compactMap { $0 } + currentDocuments)
        let documentContext = DocumentExtractionService.promptContext(from: attachments)
        let inferencePrompt = documentContext.isEmpty ? trimmedPrompt : "\(trimmedPrompt)\n\n\(documentContext)"

        // Capture history BEFORE appending the current user message so inference
        // services receive clean prior context without needing to deduplicate.
        let conversation = store.selectedSession?.messages ?? []
        let userMessage = ChatMessage(role: .user, text: trimmedPrompt, attachments: attachments)
        store.appendMessage(userMessage, to: sessionID)
        isInputFocused = false
        prompt = ""
        attachedImage = nil
        attachedDocuments = []

        let raiDecision = ResponsibleAIGuard.evaluate(prompt: trimmedPrompt)
        if raiDecision.isBlocked, let response = raiDecision.response {
            chatLogger.log("RAI guard blocked prompt: \(raiDecision.reason ?? "unknown", privacy: .public)")
            store.appendMessage(ChatMessage(role: .assistant, text: response), to: sessionID)
            return
        }

        isSending = true

        let taskID = UUID()
        activeGenerationID = taskID

        let task = Task {
            do {
                await MainActor.run {
                    idleRuntimeReleaseTask?.cancel()
                    idleRuntimeReleaseTask = nil
                }
                await RuntimeMemoryCoordinator.prepareForRuntime(model.catalogItem.runtimeType)

                let searchContext: SearchContext?
                // Search flow:
                // - liveSearchEnabled/useSearchByDefault arms web search for this turn
                // - current/live/explicit web queries get upfront search
                // - everything else stays local unless the model decides to call web_search
                // Search results are passed into the model prompt; we only fall back
                // to a grounded summary after generation if the model refuses or emits nothing usable.
                let resolvedModel = resolved(for: model)
                let toolsVerified = resolvedModel.tools != nil
                let modelCanUseToolLoop = model.catalogItem.supportsToolCalling && toolsVerified
                let isOpenELM = model.catalogItem.family == .openELM
                let searchConfigured = SearchGatewayFactory.make(settings: store.settings) != nil
                // OpenELM lane: keep fully local/minimal prompt path for stability.
                let searchArmed = !isOpenELM && (liveSearchEnabled || store.settings.useSearchByDefault)
                let shouldUpfrontSearch = searchConfigured
                    && searchArmed
                    && SearchResultFallbackComposer.shouldRunUpfrontSearch(trimmedPrompt)
                if shouldUpfrontSearch,
                   let gateway = SearchGatewayFactory.make(settings: store.settings) {
                    do {
                        searchContext = try await gateway.search(query: trimmedPrompt)
                    } catch {
                        let warning = ChatMessage(role: .system, text: "⚠️ Search failed: \(error.localizedDescription)")
                        await MainActor.run {
                            store.appendMessage(warning, to: sessionID)
                        }
                        searchContext = nil
                    }
                } else {
                    searchContext = nil
                }

                // Inject tool definition ONLY when search is configured but
                // no upfront search results are available. When upfront search
                // already returned snippets, tool definitions waste context window
                // and overwhelm small models — skip them to maximize generation room.
                var systemPromptForInference = store.settings.systemPrompt
                if searchConfigured && searchArmed && modelCanUseToolLoop && searchContext == nil {
                    systemPromptForInference += Self.toolCallDefinition
                    chatLogger.log("Tool definition injected (search configured, no upfront results)")
                } else if searchConfigured && searchArmed && !modelCanUseToolLoop {
                    chatLogger.log("Search armed, but tool definition skipped (model not tool-verified)")
                } else if searchContext != nil {
                    chatLogger.log("Upfront search provided results — tool definition skipped to save context window")
                } else {
                    chatLogger.log("Search not armed or provider unavailable — tool definition NOT injected")
                }

                // Create a placeholder assistant message for streaming
                let service = inferenceServiceForModel(model)
                let pendingCitations = searchContext?.citations ?? []
                let (messageID, stream) = try await service.generateStream(
                    prompt: inferencePrompt,
                    model: model,
                    conversation: conversation,
                    searchContext: searchContext,
                    systemPrompt: systemPromptForInference,
                    imageData: jpegData,
                    settings: store.settings
                )

                let placeholder = ChatMessage(id: messageID, role: .assistant, text: "", citations: pendingCitations)
                await MainActor.run {
                    store.appendMessage(placeholder, to: sessionID)
                }

                var accumulated = ""
                var thinkingAccumulated = ""
                var stoppedByUser = false
                let clock = ContinuousClock()
                var lastFlush = clock.now

                for await event in stream {
                    if Task.isCancelled {
                        accumulated += "\n\n*(Response stopped by user)*"
                        stoppedByUser = true
                        updateStreamingMessage(accumulated, messageID: messageID, sessionID: sessionID, persist: true)
                        break
                    }

                    switch event {
                    case .textDelta(let chunk):
                        accumulated += chunk
                        if model.catalogItem.family == .openELM {
                            break
                        }
                        let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                            || chunk.contains(where: \.isNewline)
                            || accumulated.count <= 48
                        if shouldFlush {
                            lastFlush = clock.now
                            updateStreamingMessage(accumulated, messageID: messageID, sessionID: sessionID)
                        }

                    case .thinkingDelta(let chunk):
                        thinkingAccumulated += chunk
                        let snapshot = thinkingAccumulated
                        await MainActor.run {
                            store.updateMessageThinking(messageID, in: sessionID, thinkingContent: snapshot)
                        }

                    case .thinkingDone(let duration):
                        let snapshot = thinkingAccumulated
                        await MainActor.run {
                            store.updateMessageThinking(
                                messageID, in: sessionID,
                                thinkingContent: snapshot,
                                thinkingDurationSeconds: duration,
                                persist: true
                            )
                        }

                    case .toolCall(let name, let argsJSON):
                        chatLogger.log("StreamProcessor yielded .toolCall: name=\(name, privacy: .public) argsLen=\(argsJSON.count)")
                        guard modelCanUseToolLoop else {
                            chatLogger.log("Ignoring tool call: model is not tool-verified")
                            break
                        }
                        guard name.lowercased() == "web_search" else {
                            chatLogger.log("Tool call name '\(name, privacy: .public)' is not web_search — ignoring")
                            break
                        }
                        // Parse query from multiple JSON formats:
                        // 1) {"name":"web_search","arguments":{"query":"..."}}
                        // 2) {"name":"web_search","query":"..."}
                        // 3) {"name":"web_search","arguments":"{\"query\":\"...\"}"} (string args)
                        guard let data = argsJSON.data(using: .utf8),
                              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            chatLogger.log("Failed to parse tool call JSON: \(argsJSON.prefix(200), privacy: .public)")
                            break
                        }
                        // Try nested dict arguments, then flat query, then string-encoded arguments
                        var query: String?
                        if let args = raw["arguments"] as? [String: Any] {
                            query = args["query"] as? String
                        } else if let argsStr = raw["arguments"] as? String,
                                  let argsData = argsStr.data(using: .utf8),
                                  let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                            query = argsDict["query"] as? String
                        }
                        if query == nil { query = raw["query"] as? String }
                        guard let query, !query.isEmpty else {
                            chatLogger.log("Could not extract query from tool call JSON: \(argsJSON.prefix(200), privacy: .public)")
                            break
                        }
                        chatLogger.log("Tool call parsed — query: \(query, privacy: .public)")

                        // Remove the first assistant placeholder entirely so the
                        // "No visible answer" recovery card never appears in the chat.
                        await MainActor.run { store.removeMessage(messageID, from: sessionID) }

                        let searchingMsg = ChatMessage(role: .system, text: "🔍 Searching: \(query)…")
                        await MainActor.run { store.appendMessage(searchingMsg, to: sessionID) }

                        var agenticSearchContext: SearchContext? = nil
                        if let gateway = SearchGatewayFactory.make(settings: store.settings) {
                            chatLogger.log("Calling search gateway for query: \(query, privacy: .public)")
                            do {
                                agenticSearchContext = try await gateway.search(query: query)
                                chatLogger.log("Search returned \(agenticSearchContext?.snippets.count ?? 0) snippets")
                            } catch {
                                chatLogger.log("Search gateway error: \(error.localizedDescription, privacy: .public)")
                                let errorMsg = ChatMessage(role: .system, text: "⚠️ Search failed: \(error.localizedDescription)")
                                await MainActor.run { store.appendMessage(errorMsg, to: sessionID) }
                            }
                        } else {
                            chatLogger.log("No search gateway available — factory returned nil")
                        }
                        if agenticSearchContext == nil {
                            let unavailableMsg = ChatMessage(role: .system, text: "⚠️ Search unavailable — answering from local knowledge.")
                            await MainActor.run { store.appendMessage(unavailableMsg, to: sessionID) }
                        }

                        let newPendingCitations = agenticSearchContext?.citations ?? []
                        chatLogger.log("Re-invoking inference with search context (nil=\(agenticSearchContext == nil))")
                        let (newMessageID, newStream) = try await service.generateStream(
                            prompt: inferencePrompt,
                            model: model,
                            conversation: conversation,
                            searchContext: agenticSearchContext,
                            systemPrompt: store.settings.systemPrompt,
                            imageData: jpegData,
                            settings: store.settings
                        )
                        let newPlaceholder = ChatMessage(id: newMessageID, role: .assistant, text: "", citations: newPendingCitations)
                        await MainActor.run { store.appendMessage(newPlaceholder, to: sessionID) }

                        accumulated = ""
                        thinkingAccumulated = ""
                        for await newEvent in newStream {
                            if Task.isCancelled { break }
                            switch newEvent {
                            case .textDelta(let chunk):
                                accumulated += chunk
                                let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                                    || chunk.contains(where: \.isNewline)
                                    || accumulated.count <= 48
                                if shouldFlush {
                                    lastFlush = clock.now
                                    updateStreamingMessage(accumulated, messageID: newMessageID, sessionID: sessionID)
                                }
                            case .thinkingDelta(let chunk):
                                thinkingAccumulated += chunk
                                let snapshot = thinkingAccumulated
                                await MainActor.run {
                                    store.updateMessageThinking(newMessageID, in: sessionID, thinkingContent: snapshot)
                                }
                            case .thinkingDone(let dur):
                                let snapshot = thinkingAccumulated
                                await MainActor.run {
                                    store.updateMessageThinking(newMessageID, in: sessionID, thinkingContent: snapshot, thinkingDurationSeconds: dur, persist: true)
                                }
                            case .toolCall, .done:
                                break
                            }
                        }
                        let finalText2 = searchAwareAssistantText(
                            from: accumulated,
                            prompt: trimmedPrompt,
                            thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            searchContext: agenticSearchContext
                        )
                        updateStreamingMessage(
                            finalText2,
                            messageID: newMessageID, sessionID: sessionID, persist: true
                        )
                        await MainActor.run { finishGenerationIfCurrent(taskID) }
                        return

                    case .done:
                        break
                    }
                }

                // ── Post-stream tool call fallback ──────────────────────
                // If StreamProcessor missed a <tool_call> block (e.g. tag split
                // across token boundaries), detect it in the accumulated text.
                chatLogger.log("Stream ended. accumulated length=\(accumulated.count), checking for missed tool calls…")
                if accumulated.lowercased().contains("<tool_call>") || accumulated.lowercased().contains("<|tool_call>") {
                    chatLogger.log("Post-stream: raw text contains tool_call tag")
                }
                if !stoppedByUser,
                   modelCanUseToolLoop,
                   let query = Self.extractToolCallQuery(from: accumulated),
                   SearchGatewayFactory.make(settings: store.settings) != nil {
                    chatLogger.log("Post-stream fallback FIRED — query: \(query, privacy: .public)")
                    await MainActor.run { store.removeMessage(messageID, from: sessionID) }

                    let searchingMsg = ChatMessage(role: .system, text: "🔍 Searching: \(query)…")
                    await MainActor.run { store.appendMessage(searchingMsg, to: sessionID) }

                    var agenticSearchContext: SearchContext? = nil
                    if let gateway = SearchGatewayFactory.make(settings: store.settings) {
                        chatLogger.log("Post-stream: calling search gateway…")
                        do {
                            agenticSearchContext = try await gateway.search(query: query)
                            chatLogger.log("Post-stream: search returned \(agenticSearchContext?.snippets.count ?? 0) snippets")
                        } catch {
                            chatLogger.log("Post-stream: search error: \(error.localizedDescription, privacy: .public)")
                            let errorMsg = ChatMessage(role: .system, text: "⚠️ Search failed: \(error.localizedDescription)")
                            await MainActor.run { store.appendMessage(errorMsg, to: sessionID) }
                        }
                    } else {
                        chatLogger.log("Post-stream: no search gateway available")
                    }
                    if agenticSearchContext == nil {
                        let unavailableMsg = ChatMessage(role: .system, text: "⚠️ Search unavailable — answering from local knowledge.")
                        await MainActor.run { store.appendMessage(unavailableMsg, to: sessionID) }
                    }

                    let newPendingCitations = agenticSearchContext?.citations ?? []
                    let (newMessageID, newStream) = try await service.generateStream(
                        prompt: inferencePrompt,
                        model: model,
                        conversation: conversation,
                        searchContext: agenticSearchContext,
                        systemPrompt: store.settings.systemPrompt,
                        imageData: jpegData,
                        settings: store.settings
                    )
                    let newPlaceholder = ChatMessage(id: newMessageID, role: .assistant, text: "", citations: newPendingCitations)
                    await MainActor.run { store.appendMessage(newPlaceholder, to: sessionID) }

                    accumulated = ""
                    thinkingAccumulated = ""
                    for await newEvent in newStream {
                        if Task.isCancelled { break }
                        switch newEvent {
                        case .textDelta(let chunk):
                            accumulated += chunk
                            let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                                || chunk.contains(where: \.isNewline)
                                || accumulated.count <= 48
                            if shouldFlush {
                                lastFlush = clock.now
                                updateStreamingMessage(accumulated, messageID: newMessageID, sessionID: sessionID)
                            }
                        case .thinkingDelta(let chunk):
                            thinkingAccumulated += chunk
                            let snapshot = thinkingAccumulated
                            await MainActor.run {
                                store.updateMessageThinking(newMessageID, in: sessionID, thinkingContent: snapshot)
                            }
                        case .thinkingDone(let dur):
                            let snapshot = thinkingAccumulated
                            await MainActor.run {
                                store.updateMessageThinking(newMessageID, in: sessionID, thinkingContent: snapshot, thinkingDurationSeconds: dur, persist: true)
                            }
                        case .toolCall, .done:
                            break
                        }
                    }
                    let finalText2 = searchAwareAssistantText(
                        from: accumulated,
                        prompt: trimmedPrompt,
                        thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        searchContext: agenticSearchContext
                    )
                    updateStreamingMessage(
                        finalText2,
                        messageID: newMessageID, sessionID: sessionID, persist: true
                    )
                    await MainActor.run { finishGenerationIfCurrent(taskID) }
                    return
                }

                // Sanitize the final text — this is what gets stored in conversation history,
                // so template tokens must be stripped to prevent feedback loops on next turn.
                chatLogger.log("Raw accumulated text (\(accumulated.count) chars): \(accumulated.prefix(500), privacy: .public)")
                let finalText = resolvedAssistantText(
                    from: accumulated,
                    prompt: trimmedPrompt,
                    thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                chatLogger.log("Resolved final text (\(finalText.count) chars): \(finalText.prefix(300), privacy: .public)")

                // OpenELM-specific retry path: if the first pass echoed instructions,
                // retry once with an ultra-minimal system prompt and no history/search.
                if !stoppedByUser,
                   model.catalogItem.family == .openELM,
                   (AssistantResponseFallback.isInstructionEchoMessage(finalText)
                        || AssistantResponseFallback.isLikelyOffTopicReply(finalText, prompt: trimmedPrompt)) {
                    chatLogger.log("OpenELM instruction-echo retry triggered.")
                    await MainActor.run { store.removeMessage(messageID, from: sessionID) }

                    let retryMsg = ChatMessage(role: .system, text: "🔄 Retrying OpenELM with minimal prompt…")
                    await MainActor.run { store.appendMessage(retryMsg, to: sessionID) }

                    let (retryMsgID, retryStream) = try await service.generateStream(
                        prompt: inferencePrompt,
                        model: model,
                        conversation: [],
                        searchContext: nil,
                        systemPrompt: "Answer in one short sentence.",
                        imageData: nil,
                        settings: store.settings
                    )
                    let retryPlaceholder = ChatMessage(id: retryMsgID, role: .assistant, text: "", citations: [])
                    await MainActor.run { store.appendMessage(retryPlaceholder, to: sessionID) }

                    accumulated = ""
                    thinkingAccumulated = ""
                    for await retryEvent in retryStream {
                        if Task.isCancelled { break }
                        switch retryEvent {
                        case .textDelta(let chunk):
                            accumulated += chunk
                            if model.catalogItem.family == .openELM {
                                break
                            }
                            let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                                || chunk.contains(where: \.isNewline)
                                || accumulated.count <= 48
                            if shouldFlush {
                                lastFlush = clock.now
                                updateStreamingMessage(accumulated, messageID: retryMsgID, sessionID: sessionID)
                            }
                        case .thinkingDelta(let chunk):
                            thinkingAccumulated += chunk
                        case .thinkingDone, .toolCall, .done:
                            break
                        }
                    }
                    let retryFinalText = resolvedAssistantText(
                        from: accumulated,
                        prompt: trimmedPrompt,
                        thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    let stabilizedRetryText: String
                    if AssistantResponseFallback.isInstructionEchoMessage(retryFinalText)
                        || AssistantResponseFallback.isLikelyOffTopicReply(retryFinalText, prompt: trimmedPrompt) {
                        stabilizedRetryText = AssistantResponseFallback.openELMSafeFallback(for: trimmedPrompt)
                    } else {
                        stabilizedRetryText = retryFinalText
                    }
                    updateStreamingMessage(stabilizedRetryText, messageID: retryMsgID, sessionID: sessionID, persist: true)
                    await MainActor.run { finishGenerationIfCurrent(taskID) }
                    return
                }

                // ── Search-grounding retry ──────────────────────────
                // Some small models still emit a stock "no real-time access"
                // disclaimer even when fresh web results are already in the prompt.
                // Retry once with a stricter search-grounding prompt and no history.
                if !stoppedByUser,
                   let searchContext,
                   AssistantResponseFallback.isSearchAccessRefusal(finalText) {
                    chatLogger.log("Search-grounding retry triggered after searched response refused live/current access.")
                    await MainActor.run { store.removeMessage(messageID, from: sessionID) }

                    let retryMsg = ChatMessage(role: .system, text: "🔄 Retrying with grounded web results…")
                    await MainActor.run { store.appendMessage(retryMsg, to: sessionID) }

                    let retryCitations = searchContext.citations
                    let (retryMsgID, retryStream) = try await service.generateStream(
                        prompt: inferencePrompt,
                        model: model,
                        conversation: conversation,
                        searchContext: searchContext,
                        systemPrompt: SearchGroundingGuidance.retrySystemPrompt(from: store.settings.systemPrompt),
                        imageData: nil,
                        settings: store.settings
                    )
                    let retryPlaceholder = ChatMessage(id: retryMsgID, role: .assistant, text: "", citations: retryCitations)
                    await MainActor.run { store.appendMessage(retryPlaceholder, to: sessionID) }

                    accumulated = ""
                    thinkingAccumulated = ""
                    for await retryEvent in retryStream {
                        if Task.isCancelled { break }
                        switch retryEvent {
                        case .textDelta(let chunk):
                            accumulated += chunk
                            let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                                || chunk.contains(where: \.isNewline)
                                || accumulated.count <= 48
                            if shouldFlush {
                                lastFlush = clock.now
                                updateStreamingMessage(accumulated, messageID: retryMsgID, sessionID: sessionID)
                            }
                        case .thinkingDelta(let chunk):
                            thinkingAccumulated += chunk
                            let snapshot = thinkingAccumulated
                            await MainActor.run {
                                store.updateMessageThinking(retryMsgID, in: sessionID, thinkingContent: snapshot)
                            }
                        case .thinkingDone(let dur):
                            let snapshot = thinkingAccumulated
                            await MainActor.run {
                                store.updateMessageThinking(retryMsgID, in: sessionID, thinkingContent: snapshot, thinkingDurationSeconds: dur, persist: true)
                            }
                        case .toolCall, .done:
                            break
                        }
                    }
                    let retryFinalText = searchAwareAssistantText(
                        from: accumulated,
                        prompt: trimmedPrompt,
                        thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        searchContext: searchContext
                    )
                    updateStreamingMessage(retryFinalText, messageID: retryMsgID, sessionID: sessionID, persist: true)
                    await MainActor.run { finishGenerationIfCurrent(taskID) }
                    return
                }

                // ── Empty-output fallback ───────────────────────────
                // Two branches depending on whether search was already provided:
                // A) searchContext was provided but model still failed → retry with
                //    simplified prompt (no history, no tool def) to maximize context
                // B) No search context → auto-search and retry
                if !stoppedByUser,
                   AssistantResponseFallback.isEmptyOutputMessage(finalText),
                   SearchGatewayFactory.make(settings: store.settings) != nil {

                    if searchContext != nil {
                        // ── Branch A: search was provided, model still produced nothing ──
                        // Retry with a minimal system prompt and no history to give the
                        // model maximum context window for the search results + question.
                        chatLogger.log("Empty-output retry: search context was provided but model produced nothing. Retrying with simplified prompt.")
                        await MainActor.run { store.removeMessage(messageID, from: sessionID) }

                        let retryMsg = ChatMessage(role: .system, text: "🔄 Retrying with simplified prompt…")
                        await MainActor.run { store.appendMessage(retryMsg, to: sessionID) }

                        let retryCitations = searchContext?.citations ?? []
                        let (retryMsgID, retryStream) = try await service.generateStream(
                            prompt: inferencePrompt,
                            model: model,
                            conversation: conversation,
                            searchContext: searchContext,
                            systemPrompt: SearchGroundingGuidance.retrySystemPrompt(from: store.settings.systemPrompt),
                            imageData: nil,
                            settings: store.settings
                        )
                        let retryPlaceholder = ChatMessage(id: retryMsgID, role: .assistant, text: "", citations: retryCitations)
                        await MainActor.run { store.appendMessage(retryPlaceholder, to: sessionID) }

                        accumulated = ""
                        thinkingAccumulated = ""
                        for await retryEvent in retryStream {
                            if Task.isCancelled { break }
                            switch retryEvent {
                            case .textDelta(let chunk):
                                accumulated += chunk
                                let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                                    || chunk.contains(where: \.isNewline)
                                    || accumulated.count <= 48
                                if shouldFlush {
                                    lastFlush = clock.now
                                    updateStreamingMessage(accumulated, messageID: retryMsgID, sessionID: sessionID)
                                }
                            case .thinkingDelta(let chunk):
                                thinkingAccumulated += chunk
                                let snapshot = thinkingAccumulated
                                await MainActor.run {
                                    store.updateMessageThinking(retryMsgID, in: sessionID, thinkingContent: snapshot)
                                }
                            case .thinkingDone(let dur):
                                let snapshot = thinkingAccumulated
                                await MainActor.run {
                                    store.updateMessageThinking(retryMsgID, in: sessionID, thinkingContent: snapshot, thinkingDurationSeconds: dur, persist: true)
                                }
                            case .toolCall, .done:
                                break
                            }
                        }
                        let retryFinalText = searchAwareAssistantText(
                            from: accumulated,
                            prompt: trimmedPrompt,
                            thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            searchContext: searchContext
                        )
                        updateStreamingMessage(retryFinalText, messageID: retryMsgID, sessionID: sessionID, persist: true)
                        await MainActor.run { finishGenerationIfCurrent(taskID) }
                        return

                    } else if let gateway = SearchGatewayFactory.make(settings: store.settings) {
                        // ── Branch B: no search was done → auto-search and retry ──
                        chatLogger.log("Empty-output auto-search fallback triggered for: \(trimmedPrompt, privacy: .public)")
                        await MainActor.run { store.removeMessage(messageID, from: sessionID) }

                        let searchingMsg = ChatMessage(role: .system, text: "🔍 Searching: \(trimmedPrompt)…")
                        await MainActor.run { store.appendMessage(searchingMsg, to: sessionID) }

                        var fallbackSearchContext: SearchContext? = nil
                        do {
                            fallbackSearchContext = try await gateway.search(query: trimmedPrompt)
                            chatLogger.log("Auto-search fallback returned \(fallbackSearchContext?.snippets.count ?? 0) snippets")
                        } catch {
                            chatLogger.log("Auto-search fallback error: \(error.localizedDescription, privacy: .public)")
                            let errorMsg = ChatMessage(role: .system, text: "⚠️ Search failed: \(error.localizedDescription)")
                            await MainActor.run { store.appendMessage(errorMsg, to: sessionID) }
                        }

                        if let fallbackSearchContext {
                            let fallbackCitations = fallbackSearchContext.citations
                            let (fbMessageID, fbStream) = try await service.generateStream(
                                prompt: inferencePrompt,
                                model: model,
                                conversation: conversation,
                                searchContext: fallbackSearchContext,
                                systemPrompt: store.settings.systemPrompt,
                                imageData: jpegData,
                                settings: store.settings
                            )
                            let fbPlaceholder = ChatMessage(id: fbMessageID, role: .assistant, text: "", citations: fallbackCitations)
                            await MainActor.run { store.appendMessage(fbPlaceholder, to: sessionID) }

                            accumulated = ""
                            thinkingAccumulated = ""
                            for await fbEvent in fbStream {
                                if Task.isCancelled { break }
                                switch fbEvent {
                                case .textDelta(let chunk):
                                    accumulated += chunk
                                    let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                                        || chunk.contains(where: \.isNewline)
                                        || accumulated.count <= 48
                                    if shouldFlush {
                                        lastFlush = clock.now
                                        updateStreamingMessage(accumulated, messageID: fbMessageID, sessionID: sessionID)
                                    }
                                case .thinkingDelta(let chunk):
                                    thinkingAccumulated += chunk
                                    let snapshot = thinkingAccumulated
                                    await MainActor.run {
                                        store.updateMessageThinking(fbMessageID, in: sessionID, thinkingContent: snapshot)
                                    }
                                case .thinkingDone(let dur):
                                    let snapshot = thinkingAccumulated
                                    await MainActor.run {
                                        store.updateMessageThinking(fbMessageID, in: sessionID, thinkingContent: snapshot, thinkingDurationSeconds: dur, persist: true)
                                    }
                                case .toolCall, .done:
                                    break
                                }
                            }
                            let fbFinalText = searchAwareAssistantText(
                                from: accumulated,
                                prompt: trimmedPrompt,
                                thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                searchContext: fallbackSearchContext
                            )
                            updateStreamingMessage(fbFinalText, messageID: fbMessageID, sessionID: sessionID, persist: true)
                            await MainActor.run { finishGenerationIfCurrent(taskID) }
                            return
                        }
                    }
                }

                let persistedFinalText = searchAwareAssistantText(
                    from: accumulated,
                    prompt: trimmedPrompt,
                    thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    searchContext: searchContext
                )

                updateStreamingMessage(persistedFinalText, messageID: messageID, sessionID: sessionID, persist: true)

                if !stoppedByUser,
                   store.settings.voiceModeEnabled,
                   store.settings.autoPlayVoiceResponses,
                   !AssistantResponseFallback.isEmptyOutputMessage(persistedFinalText) {
                    await MainActor.run {
                        voiceController.speak(persistedFinalText, using: store.settings)
                    }
                }

                await MainActor.run {
                    finishGenerationIfCurrent(taskID)
                }
            } catch {
                if !Task.isCancelled {
                    let errorMessage = ChatMessage(role: .assistant, text: error.localizedDescription)
                    await MainActor.run {
                        store.appendMessage(errorMessage, to: sessionID)
                    }
                }
                await MainActor.run {
                    finishGenerationIfCurrent(taskID)
                }
            }
        }
        generationTask = task
    }

    /// Heuristic: returns true when the question likely needs live/current data.
    /// Uses whole-word matching to avoid false positives (e.g. "game" matching "gameplay").
    static func looksLikeRealTimeQuery(_ text: String) -> Bool {
        let lower = text.lowercased()
        let wordCount = lower.split(separator: " ").count
        // Very short messages or greetings — never auto-search
        if wordCount <= 4 { return false }

        // High-confidence multi-word signals — always search
        let phrases = [
            "right now", "latest news", "breaking news", "live score", "live update",
            "today's news", "today's score", "today's match", "today's game", "today's weather",
            "today's price", "current score", "current price", "current news",
            "trending now", "what happened", "recent news", "latest update",
            "stock price", "match result", "election result",
            "who won", "who is winning", "what is the score", "weather today",
            "news today", "cricket score", "football score", "nba score", "ipl score",
            "ipl match", "ipl today"
        ]
        if phrases.contains(where: { lower.contains($0) }) { return true }

        // Single-word signals — only when paired with a question indicator
        let hasQuestion = lower.hasPrefix("what") || lower.hasPrefix("who") ||
                          lower.hasPrefix("when") || lower.hasPrefix("where") ||
                          lower.contains("?")
        if !hasQuestion { return false }

        // Whole-word check via regex word boundaries
        let singleWordSignals = ["ipl", "cricket", "nba", "nfl", "premier league", "standings"]
        for signal in singleWordSignals {
            if let _ = lower.range(of: "\\b\(signal)\\b", options: .regularExpression) { return true }
        }
        // Year with question
        if lower.contains("2025") || lower.contains("2026") { return true }
        return false
    }
}
