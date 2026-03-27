import SwiftUI

struct ChatView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.selectedTab) private var selectedTab
    @State private var prompt = ""
    @State private var liveSearchEnabled = false
    @State private var isInputFocused = false
    @State private var isSending = false
    @State private var generationTask: Task<Void, Never>?
    @State private var activeGenerationID: UUID?
    @State private var inferenceService: InferenceService = LocalLlamaInferenceService()
    @State private var mlxInferenceService: InferenceService = MLXInferenceService()
    @State private var showModelPicker = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var attachedImage: UIImage?
    @StateObject private var voiceController = VoiceInteractionController()

    private let streamUpdateInterval: Duration = .milliseconds(80)

    private var composerBottomSpacing: CGFloat {
        isInputFocused ? 8 : 78
    }

    private var isCompactHeader: Bool {
        isInputFocused && !activeMessages.isEmpty
    }

    private var isVisionModel: Bool {
        guard let model = store.defaultModel else { return false }
        // Only enable vision UI for MLX models — GGUF runtime has no image pipeline
        return model.catalogItem.supportsVision && model.catalogItem.runtimeType == .mlx
    }

    private var lastAssistantResponseText: String? {
        activeMessages
            .last(where: { $0.role == .assistant })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferenceServiceForModel(_ model: InstalledModel) -> InferenceService {
        model.catalogItem.runtimeType == .mlx ? mlxInferenceService : inferenceService
    }

    var body: some View {
        ZStack {
            AppTheme.meshBackground.ignoresSafeArea()
            AppTheme.glow.opacity(0.18).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if activeMessages.isEmpty {
                    VStack {
                        Spacer(minLength: 0)
                        emptyState
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .scale(scale: 1.1).combined(with: .opacity)
                                )
                            )
                        Spacer(minLength: 0)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(activeMessages) { message in
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }

                                if isSending {
                                    HStack {
                                        TypingIndicator()
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 14)
                                            .background(AppTheme.panel.opacity(0.85))
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(AppTheme.hairline, lineWidth: 1)
                                            )
                                        Spacer()
                                    }
                                    .id("typing")
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isInputFocused = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab.wrappedValue = 2
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(8)
                        .background(AppTheme.panel.opacity(0.6))
                        .clipShape(Circle())
                }
                .accessibilityLabel("View chat history")
            }
            ToolbarItem(placement: .principal) {
                Text("Chat")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isInputFocused = false
                    store.createSession(using: store.defaultModel?.catalogItem.id)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .padding(8)
                        .background(AppTheme.panel.opacity(0.6))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Start new chat")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposerView(
                prompt: $prompt,
                liveSearchEnabled: $liveSearchEnabled,
                attachedImage: $attachedImage,
                isInputFocused: $isInputFocused,
                voiceModeEnabled: store.settings.voiceModeEnabled,
                isListening: voiceController.isListening,
                voiceStatusMessage: voiceController.lastError,
                isVisionModel: isVisionModel,
                isSending: isSending,
                isSearchConfigured: SearchGatewayFactory.make(settings: store.settings) != nil,
                onSend: sendPrompt,
                onToggleVoiceInput: toggleVoiceInput,
                onStop: stopGeneration
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
        .onAppear { store.reconcileInstalledFiles() }
        .onChange(of: voiceController.transcript) {
            if voiceController.isListening {
                prompt = voiceController.transcript
            }
        }
        .onChange(of: store.settings.voiceModeEnabled) {
            if !store.settings.voiceModeEnabled {
                voiceController.stopListening()
                voiceController.stopSpeaking()
            }
        }
    }

    private var activeMessages: [ChatMessage] {
        store.selectedSession?.messages ?? []
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            // Model selector
            Button {
                showModelPicker = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    Text(store.defaultModel?.catalogItem.displayName ?? "Select model")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    if let runtime = store.defaultModel?.catalogItem.runtimeType {
                        Text(runtime.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(runtime == .mlx ? .orange : AppTheme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(runtime == .mlx ? Color.orange.opacity(0.12) : AppTheme.panelRaised)
                            .clipShape(Capsule())
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Capability pills — only when not compact
            if !isCompactHeader, let model = store.defaultModel {
                HStack(spacing: 4) {
                    if model.catalogItem.supportsVision {
                        capabilityBadge(icon: "eye", label: "Vision", active: true, color: .purple)
                    }
                    if model.catalogItem.isThinkingModel {
                        capabilityBadge(icon: "lightbulb.max", label: "Think", active: true, color: .yellow)
                    }
                    if model.catalogItem.supportsToolCalling {
                        capabilityBadge(icon: "wrench.and.screwdriver", label: "Tools", active: true, color: .green)
                    }
                }
            }

            // Status pill
            HStack(spacing: 4) {
                Circle()
                    .fill(liveSearchEnabled ? AppTheme.warning : AppTheme.success)
                    .frame(width: 5, height: 5)
                    .animation(
                        liveSearchEnabled
                            ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                            : .default,
                        value: liveSearchEnabled
                    )
                Text(liveSearchEnabled ? "Search" : "Offline")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(liveSearchEnabled ? AppTheme.warning : AppTheme.success)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.panel.opacity(0.8))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppTheme.hairline, lineWidth: 1))

            if store.settings.voiceModeEnabled, let lastAssistantResponseText, !lastAssistantResponseText.isEmpty {
                Button {
                    replayLastAssistantResponse()
                } label: {
                    Image(systemName: voiceController.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(voiceController.isSpeaking ? AppTheme.warning : AppTheme.accent)
                        .padding(7)
                        .background(AppTheme.panel.opacity(0.8))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.hairline, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            AppTheme.background.opacity(0.65)
                .background(.ultraThinMaterial)
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isCompactHeader)
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func capabilityBadge(icon: String, label: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(active ? color : AppTheme.textTertiary.opacity(0.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(active ? color.opacity(0.12) : AppTheme.panelRaised.opacity(0.5))
        )
        .overlay(
            Capsule()
                .stroke(active ? color.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Model Picker Sheet

    private var modelPickerSheet: some View {
        NavigationStack {
            List {
                let readyModels = store.availableChatModels
                if readyModels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(AppTheme.textTertiary)
                        Text("No models installed")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("Download a model from the Library tab")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textTertiary)

                        Button {
                            showModelPicker = false
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedTab.wrappedValue = 1
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 12))
                                Text("Go to Library")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent.opacity(0.15))
                            .foregroundStyle(AppTheme.accent)
                            .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(readyModels, id: \.catalogItem.id) { model in
                        let isSelected = store.defaultModel?.catalogItem.id == model.catalogItem.id
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: model.catalogItem.runtimeType.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                                    .frame(width: 32, height: 32)
                                    .background(isSelected ? AppTheme.accent.opacity(0.15) : AppTheme.accent.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.catalogItem.displayName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text("\(model.catalogItem.family.lab) \u{2022} \(model.catalogItem.runtimeType.label) \u{2022} \(model.catalogItem.parameterSize) \u{2022} \(model.catalogItem.diskSize)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }

                            // Model summary
                            Text(model.catalogItem.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(2)

                            // Capability badges
                            HStack(spacing: 4) {
                                if model.catalogItem.supportsVision {
                                    pickerBadge("eye", "Vision", .purple)
                                }
                                if model.catalogItem.supportsReasoning {
                                    pickerBadge("brain.head.profile", "Reasoning", .cyan)
                                }
                                if model.catalogItem.isThinkingModel {
                                    pickerBadge("lightbulb.max", "Thinking", .yellow)
                                }
                                if model.catalogItem.supportsToolCalling {
                                    pickerBadge("wrench.and.screwdriver", "Tools", .green)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.setDefaultModel(id: model.catalogItem.id)
                            showModelPicker = false
                        }
                    }
                }
            }
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

    private func pickerBadge(_ icon: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 28) {
            ZStack {
                // Animated gradient glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.accent.opacity(0.3),
                                AppTheme.accentSoft.opacity(0.2),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)
                
                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppTheme.accent.opacity(0.5),
                                AppTheme.accentSoft.opacity(0.3),
                                AppTheme.accent.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 120, height: 120)
                
                // Inner circle with glassmorphism
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.18, blue: 0.25).opacity(0.8),
                                Color(red: 0.10, green: 0.12, blue: 0.20).opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                // Icon
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                AppTheme.accent,
                                AppTheme.accentSoft
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: AppTheme.accent.opacity(0.4), radius: 12, x: 0, y: 4)
            }

            VStack(spacing: 10) {
                Text("Start a Conversation")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(store.defaultModel == nil
                     ? "Install a model from the library to begin"
                     : "Ask anything — everything runs on-device")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if store.defaultModel == nil {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab.wrappedValue = 1
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Browse Models")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(
                        ZStack {
                            // Glow
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AppTheme.accent.opacity(0.4),
                                            AppTheme.accentSoft.opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blur(radius: 10)
                            
                            // Main button
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AppTheme.accent,
                                            AppTheme.accentSoft
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(40)
    }

    private func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        isSending = false
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

    private func cleanedDisplayedAssistantText(_ text: String) -> String {
        AssistantResponseSanitizer.clean(text)
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
    private func updateStreamingMessage(_ text: String, messageID: UUID, sessionID: UUID, persist: Bool = false) {
        store.updateMessageText(messageID, in: sessionID, text: text, persist: persist)
    }

    @MainActor
    private func finishGenerationIfCurrent(_ taskID: UUID) {
        guard activeGenerationID == taskID else { return }
        isSending = false
        generationTask = nil
        activeGenerationID = nil
    }

    private func sendPrompt() {
        guard !isSending else { return }
        voiceController.stopListening()

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentImage = attachedImage
        guard !trimmedPrompt.isEmpty || currentImage != nil else { return }
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

        // Encode image at bounded size to avoid memory spikes during persistence/inference.
        let jpegData = encodedAttachmentData(from: currentImage)

        let userMessage = ChatMessage(role: .user, text: trimmedPrompt, imageData: jpegData)
        store.appendMessage(userMessage, to: sessionID)
        let conversation = store.selectedSession?.messages ?? [userMessage]
        isInputFocused = false
        prompt = ""
        attachedImage = nil
        isSending = true

        let taskID = UUID()
        activeGenerationID = taskID

        let task = Task {
            do {
                let searchContext: SearchContext?
                if liveSearchEnabled || store.settings.useSearchByDefault,
                   let gateway = SearchGatewayFactory.make(settings: store.settings) {
                    do {
                        searchContext = try await gateway.search(query: trimmedPrompt)
                    } catch {
                        // Search failed — show brief warning but continue with model
                        let warning = ChatMessage(role: .system, text: "⚠️ Search failed: \(error.localizedDescription)")
                        await MainActor.run {
                            store.appendMessage(warning, to: sessionID)
                        }
                        searchContext = nil
                    }
                } else {
                    searchContext = nil
                }

                // Create a placeholder assistant message for streaming
                let service = inferenceServiceForModel(model)
                let (messageID, citations, stream) = try await service.generateStream(
                    prompt: trimmedPrompt,
                    model: model,
                    conversation: conversation,
                    searchContext: searchContext,
                    systemPrompt: store.settings.systemPrompt,
                    imageData: jpegData
                )

                let placeholder = ChatMessage(id: messageID, role: .assistant, text: "", citations: citations)
                await MainActor.run {
                    store.appendMessage(placeholder, to: sessionID)
                }

                var accumulated = ""
                var stoppedByUser = false
                let clock = ContinuousClock()
                var lastFlush = clock.now
                for await piece in stream {
                    if Task.isCancelled {
                        accumulated += "\n\n*(Response stopped by user)*"
                        stoppedByUser = true
                        await updateStreamingMessage(accumulated, messageID: messageID, sessionID: sessionID, persist: true)
                        break
                    }

                    accumulated += piece

                    let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                        || piece.contains(where: \ .isNewline)
                        || accumulated.count <= 48

                    guard shouldFlush else {
                        continue
                    }

                    lastFlush = clock.now
                    await updateStreamingMessage(accumulated, messageID: messageID, sessionID: sessionID)
                }

                // Sanitize the final text — this is what gets stored in conversation history,
                // so template tokens must be stripped to prevent feedback loops on next turn.
                let finalText = cleanedDisplayedAssistantText(accumulated)
                if finalText.isEmpty {
                    let fallback = "The model finished without returning text. Try a shorter prompt or another model."
                    await updateStreamingMessage(fallback, messageID: messageID, sessionID: sessionID, persist: true)
                } else {
                    await updateStreamingMessage(finalText, messageID: messageID, sessionID: sessionID, persist: true)
                }

                if !stoppedByUser,
                   store.settings.voiceModeEnabled,
                   store.settings.autoPlayVoiceResponses,
                   !finalText.isEmpty {
                    await MainActor.run {
                        voiceController.speak(finalText, using: store.settings)
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

    private func resolveSearchContext(for prompt: String) async -> SearchContext? {
        guard liveSearchEnabled || store.settings.useSearchByDefault else { return nil }
        guard let gateway = SearchGatewayFactory.make(settings: store.settings) else { return nil }
        return try? await gateway.search(query: prompt)
    }
}
