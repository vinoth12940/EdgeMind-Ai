import SwiftUI


enum ChatInputCapability {
    static let imageUnsupportedMessage = "This model supports text and document prompts only. Choose a vision model such as Qwen 3.5 VL, LFM2.5 VL, or Gemma 4 LiteRT-LM to ask about an image."

    static func acceptsImage(_ model: InstalledModel, profileStore: RuntimeProfileStore) -> Bool {
        ModelRuntimeResolver.resolve(catalog: model.catalogItem, store: profileStore).vision == .imageAndText
    }
}

enum ChatVisionContext {
    static func inheritedImageData(
        explicitImageData: Data?,
        prompt: String,
        conversation: [ChatMessage],
        model: InstalledModel,
        profileStore: RuntimeProfileStore
    ) -> Data? {
        if let explicitImageData { return explicitImageData }
        guard ChatInputCapability.acceptsImage(model, profileStore: profileStore),
              isVisualFollowUp(prompt: prompt) else {
            return nil
        }
        return latestImageData(in: conversation)
    }

    private static func latestImageData(in conversation: [ChatMessage]) -> Data? {
        for message in conversation.reversed() where message.role == .user {
            if let imageData = message.imageData {
                return imageData
            }
        }
        return nil
    }

    private static func isVisualFollowUp(prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        let compact = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return false }

        let visualTerms = [
            "image", "picture", "photo", "wearing", "shirt", "hat", "cap", "cab",
            "color", "colour", "person", "boy", "girl", "man", "woman", "kid",
            "dinosaur", "background", "behind", "front", "left", "right", "above",
            "below", "this", "that", "he", "she", "they", "it"
        ]

        return visualTerms.contains { normalized.contains($0) }
            || normalized.hasPrefix("what about")
            || normalized.hasPrefix("what is")
            || normalized.hasPrefix("what's")
            || normalized.hasPrefix("describe")
    }
}

struct ChatView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(ChatTurnEngine.self) private var engine
    @Environment(\.selectedTab) private var selectedTab
    @Environment(\.scenePhase) private var scenePhase
    @State private var prompt = ""
    @State private var liveSearchEnabled = false
    @State private var searchAutoInitialized = false
    @State private var isInputFocused = false
    @State private var showModelPicker = false
    @State private var showDeleteCurrentSessionConfirmation = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var attachedImage: UIImage?
    /// User message being edited; while set, Send edits-and-resends instead of appending.
    @State private var editingMessage: ChatMessage?
    @State private var showEditConfirmation = false
    @State private var showExportSheet = false
    /// Suppresses the task-based model suggestion for the rest of the session.
    @State private var dismissedModelSuggestion = false
    @State private var attachedDocuments: [ChatAttachment] = []
    @StateObject private var voiceController = VoiceInteractionController()


    private func resolved(for model: InstalledModel) -> ResolvedModel {
        ModelRuntimeResolver.resolve(catalog: model.catalogItem, store: engine.profileStore)
    }


    private var composerBottomSpacing: CGFloat {
        isInputFocused ? 4 : 8
    }

    private var isVisionModel: Bool {
        guard let model = store.defaultModel else { return false }
        // Runtime profile is the gate here. Source/model-card vision claims are
        // not enough to keep image attachments enabled after a red device audit.
        return ChatInputCapability.acceptsImage(model, profileStore: engine.profileStore)
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

        if model.catalogItem.sourceSupportsVision && resolved(for: model).vision != .imageAndText {
            return "\(model.catalogItem.displayName) supports multimodal inputs upstream, but this app has not verified a memory-stable image path for this phone. Text chat stays enabled; choose a green vision model for image prompts."
        }

        return nil
    }

    private var activeContextDisplay: String {
        guard let model = activeModel else { return "None" }
        return Self.formattedTokenWindow(InferenceBudget.safeContextWindow(for: model))
    }

    private var activeContextDetail: String {
        guard let model = activeModel else { return "No model" }
        if model.catalogItem.contextWindowTokenCount > InferenceBudget.safeContextWindow(for: model) {
            return "Device-safe"
        }
        return "Runtime window"
    }

    private static func formattedTokenWindow(_ tokens: Int) -> String {
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K"
        }
        return "\(tokens)"
    }


    private var lastAssistantResponseText: String? {
        activeMessages
            .last(where: { $0.role == .assistant })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                            .padding(.bottom, 16)
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
                                    MessageBubbleView(
                                        message: message,
                                        isGenerating: message.id == activeMessages.last?.id && engine.isGenerating,
                                        showGenerationStats: store.settings.showGenerationStats,
                                        regenerateModels: store.availableChatModels,
                                        currentModelName: activeModel?.catalogItem.displayName,
                                        onRegenerate: { model in
                                            regenerate(message, model: model)
                                        },
                                        onSelectVersion: { index in
                                            guard let sessionID = store.selectedSession?.id else { return }
                                            store.selectVersion(index, of: message.id, in: sessionID)
                                        },
                                        onEdit: {
                                            beginEditing(message)
                                        }
                                    )
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }

                                if engine.isGenerating {
                                    generationStatusCard
                                    .id("typing")
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        // Do NOT use `.defaultScrollAnchor(.bottom)` here: on iOS 26.6.1
                        // devices it sends LazyVStack placement into an endless layout loop
                        // at first render, and the scene-create watchdog (0x8BADF00D) kills
                        // the app on launch whenever a saved chat has messages.
                        .onAppear {
                            scrollProxy = proxy
                            proxy.scrollTo(activeMessages.last?.id, anchor: .bottom)
                        }
                        .onChange(of: activeMessages.count) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(activeMessages.last?.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: engine.isGenerating) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                if engine.isGenerating {
                                    proxy.scrollTo("typing", anchor: .bottom)
                                } else {
                                    proxy.scrollTo(activeMessages.last?.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                if let suggestion = modelSuggestion {
                    modelSuggestionBanner(suggestion)
                }

                if editingMessage != nil {
                    editingBanner
                }

                // ChatComposerView integrated directly at bottom of VStack
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
                    isSending: engine.isGenerating,
                    isSearchConfigured: searchGatewayConfigured,
                    onSend: sendPrompt,
                    onToggleVoiceInput: toggleVoiceInput,
                    onStop: engine.stop
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
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .floatingDockHidden()
        .onAppear {
            store.reconcileInstalledFiles()
            engine.speaker = { [voiceController] text, settings in
                voiceController.speak(text, using: settings)
            }
            applyIntentHandoff()
            if !searchAutoInitialized {
                searchAutoInitialized = true
                liveSearchEnabled = SearchGatewayFactory.shouldAutoEnableLiveSearch(settings: store.settings)
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            engine.handleMemoryWarning()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                if !engine.isGenerating {
                    Task {
                        await engine.releaseRuntimes()
                    }
                }
            }
        }
        .onChange(of: store.settings.voiceModeEnabled) {            if !store.settings.voiceModeEnabled {
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
        .onChange(of: store.selectedSessionID) {
            editingMessage = nil
        }
        .alert("Delete Conversation", isPresented: $showDeleteCurrentSessionConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentSession()
            }
        } message: {
            Text("This removes the current chat from local history.")
        }
        .alert("Edit message?", isPresented: $showEditConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Edit & Send", role: .destructive) {
                performEditSend()
            }
        } message: {
            Text("Every reply after this message will be removed and the edited message will be sent again.")
        }
    }

    /// Task-based model advice (spec §3). Pure function; nil when the current
    /// model is fine or the banner was dismissed for this session.
    private var modelSuggestion: ModelSuggestion? {
        guard !dismissedModelSuggestion, let current = store.defaultModel else { return nil }
        return ModelSuggestionAdvisor.suggestion(
            prompt: prompt,
            hasImage: attachedImage != nil,
            hasDocuments: !attachedDocuments.isEmpty,
            current: current,
            installed: store.installedModels,
            profiles: engine.profileStore,
            tier: DeviceTier.current()
        )
    }

    private func modelSuggestionBanner(_ suggestion: ModelSuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.reason.message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Try \(suggestion.model.catalogItem.displayName)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("Switch") {
                store.setDefaultModel(id: suggestion.model.catalogItem.id)
                engine.prewarmDefaultModel()
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)

            Button {
                dismissedModelSuggestion = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss model suggestion")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.panelRaised.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    /// Banner shown above the composer while editing a previous user message.
    private var editingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .bold))
            Text("Editing — later replies will be removed")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button("Cancel") {
                editingMessage = nil
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(AppTheme.subtleFill))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
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

    private func deleteCurrentSession() {
        guard let sessionID = store.selectedSession?.id else { return }
        if engine.isGenerating {
            engine.stop()
        }
        isInputFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            store.deleteSession(sessionID)
        }
    }

    private var compactTopBar: some View {
        HStack {
            // Sidebar Toggle
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    store.isSidebarOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open history sidebar")
            
            Spacer()
            
            // Model Picker (Centered Quick-Switcher)
            let switchableModels = store.availableChatModels
            Menu {
                if !switchableModels.isEmpty {
                    Section("Switch Model") {
                        ForEach(switchableModels) { model in
                            Button {
                                store.setDefaultModel(id: model.catalogItem.id)
                                Task {
                                    await RuntimeMemoryCoordinator.prepareForRuntime(model.catalogItem.runtimeType)
                                }
                                engine.prewarmDefaultModel()
                            } label: {
                                Label(
                                    model.catalogItem.displayName,
                                    systemImage: activeModel?.catalogItem.id == model.catalogItem.id ? "checkmark" : model.catalogItem.runtimeType.icon
                                )
                            }
                        }
                    }
                }
                Button {
                    showModelPicker = true
                } label: {
                    Label("All Models & Downloads…", systemImage: "square.stack.3d.up")
                }
            } label: {
                HStack(spacing: 5) {
                    if let activeModel {
                        Image(systemName: activeModel.catalogItem.runtimeType.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.labColor(for: activeModel.catalogItem.family))
                    }
                    Text(activeModel?.catalogItem.displayName ?? "Select Model")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppTheme.controlFill)
                )
            }
            .buttonStyle(.plain)
            .disabled(engine.isGenerating)
            .opacity(engine.isGenerating ? 0.6 : 1.0)
            .accessibilityLabel("Active model: \(activeModel?.catalogItem.displayName ?? "No model selected"). Quick model switcher")
            .accessibilityHint("Double-tap to switch between installed models or open model library")
            
            Spacer()
            
            HStack(spacing: 2) {
                if store.selectedSession != nil {
                    Menu {
                        Button {
                            showExportSheet = true
                        } label: {
                            Label("Share chat…", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: 38, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Chat options")

                    Button {
                        showDeleteCurrentSessionConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.31, blue: 0.31))
                            .frame(width: 38, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete current chat")
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        store.createSession(using: store.defaultModel?.catalogItem.id)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 38, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start new chat")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExportSheet) {
            if let session = store.selectedSession {
                ChatExportSheet(session: session)
            }
        }
    }

    private var sessionOverviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                sessionMetricCard(
                    title: "Runtime",
                    value: activeModel?.catalogItem.runtimeType.label ?? "No runtime",
                    detail: activeModel?.catalogItem.parameterSize ?? "Browse MLX",
                    color: activeModel?.catalogItem.runtimeType == .mlx ? AppTheme.accent : AppTheme.warning
                )
                sessionMetricCard(
                    title: "Context",
                    value: activeContextDisplay,
                    detail: activeContextDetail,
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
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab.wrappedValue = 1
                    }
                } label: {
                    sessionMetricCard(
                        title: "Library",
                        value: "MLX Models",
                        detail: "Browse providers",
                        color: AppTheme.accent
                    )
                }
                .buttonStyle(.plain)
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
                            colors: [AppTheme.accent.opacity(0.26), AppTheme.surfaceStroke],
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
                            headerChip(label: activeContextDisplay, tone: .neutral)
                            headerChip(label: model.catalogItem.runtimeType.label, tone: model.catalogItem.runtimeType == .mlx ? .accent : .neutral)
                            let runtimeVisionReady = resolved(for: model).vision == .imageAndText
                            headerChip(label: runtimeVisionReady ? "Image ready" : "Text", tone: runtimeVisionReady ? .accent : .neutral)

                            if resolved(for: model).tools != nil {
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
                                .background(AppTheme.subtleFill)
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
                        .fill(AppTheme.controlFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.surfaceStroke, lineWidth: 1)
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
                .stroke(AppTheme.surfaceStroke, lineWidth: 0.8)
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
                .background(Circle().fill(AppTheme.subtleFill))
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
            fill = AppTheme.subtleFill
            foreground = AppTheme.textSecondary
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
                Section {
                    Button {
                        showModelPicker = false
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            selectedTab.wrappedValue = 1
                        }
                    } label: {
                        Label("Browse curated local models", systemImage: "shippingbox.fill")
                    }
                } header: {
                    Label("Find Local Models", systemImage: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .textCase(nil)
                }

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName), \(item.parameterSize), \(item.runtimeType.label)")
        .accessibilityAddTraits(isInstalled ? .isButton : [])
        .accessibilityHint(isInstalled ? "Select this model for chat" : "Go to model library to download")
        .onTapGesture {
            if isInstalled {
                store.setDefaultModel(id: item.id)
                showModelPicker = false
                engine.prewarmDefaultModel()
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
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return VStack(spacing: 16) {
            Spacer(minLength: 12)
            
            // Centered Brand & Logo
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentGradient.opacity(0.12))
                        .frame(width: 56, height: 56)
                        .blur(radius: 4)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.accentGradient)
                }

                Text(activeModel == nil ? "Start a local conversation" : "What can I help with?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                
                if let model = activeModel {
                    Text(model.catalogItem.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 10)
            
            // Model Info Chips (Centered)
            if let model = activeModel {
                HStack(spacing: 6) {
                    emptyStateMetaPill(label: model.catalogItem.parameterSize)
                    emptyStateMetaPill(label: model.catalogItem.runtimeType.label)
                    emptyStateMetaPill(label: resolved(for: model).vision == .imageAndText ? "Vision Ready" : "Text Only")
                    if model.catalogItem.supportsReasoning || model.catalogItem.isThinkingModel {
                        emptyStateMetaPill(label: "Reasoning")
                    }
                }
            }
            
            Spacer(minLength: 12)
            
            // Info Row (Minimal)
            HStack(spacing: 12) {
                emptyStateFeature(icon: "lock.shield.fill", title: "100% Private", detail: "On-device processing", color: AppTheme.success)
                emptyStateFeature(icon: "globe", title: "Web Grounding", detail: searchGatewayConfigured ? "Grounding ready" : "Offline mode", color: searchStatusColor)
            }
            .padding(.horizontal, 8)
            
            // Bottom Prompt Starters
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
                
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(promptStarters) { starter in
                        Button {
                            primePrompt(starter)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: starter.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.accent)
                                
                                Spacer(minLength: 2)
                                
                                Text(starter.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                
                                Text(starter.subtitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 78, alignment: .topLeading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.subtleFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.cardStroke, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func emptyStateMetaPill(label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.subtleFill)
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

    private func sendPrompt() {
        guard !engine.isGenerating else { return }
        voiceController.stopListening()
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || attachedImage != nil || !attachedDocuments.isEmpty else { return }

        // Editing a previous message removes every later reply first, so confirm.
        if editingMessage != nil {
            showEditConfirmation = true
            return
        }

        if store.selectedSession == nil {
            store.createSession(using: store.defaultModel?.catalogItem.id)
        }
        guard let sessionID = store.selectedSession?.id else { return }
        let request = TurnRequest(
            sessionID: sessionID,
            prompt: trimmedPrompt,
            attachments: attachedDocuments,
            image: attachedImage,
            liveSearchEnabled: liveSearchEnabled
        )
        if engine.preflightBlockMessage(hasImage: attachedImage != nil) != nil {
            // The engine writes the blocking notice. Leave the composer contents
            // intact so the user can fix the problem without retyping.
            engine.send(request)
            return
        }
        isInputFocused = false
        prompt = ""
        attachedImage = nil
        attachedDocuments = []
        engine.send(request)
    }

    /// Removes the edited message and everything after it, then sends the
    /// composer contents (which hold the edited text and attachments).
    private func performEditSend() {
        guard let editing = editingMessage else { return }
        if let sessionID = store.selectedSession?.id {
            store.removeMessagesForEdit(from: editing.id, in: sessionID)
        }
        editingMessage = nil
        sendPrompt()
    }

    private func beginEditing(_ message: ChatMessage) {
        guard !engine.isGenerating, message.role == .user else { return }
        editingMessage = message
        prompt = message.text
        attachedImage = message.imageData.flatMap { UIImage(data: $0) }
        attachedDocuments = message.attachments.filter { $0.kind != .image }
        isInputFocused = true
    }

    private func regenerate(_ message: ChatMessage, model: InstalledModel?) {
        guard !engine.isGenerating else { return }
        guard let sessionID = store.selectedSession?.id else { return }
        engine.send(TurnRequest(
            sessionID: sessionID,
            prompt: "",
            attachments: [],
            image: nil,
            liveSearchEnabled: liveSearchEnabled,
            target: .regenerate(assistantMessageID: message.id, model: model)
        ))
    }
}
