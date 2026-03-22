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
        store.defaultModel?.catalogItem.supportsVision == true
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
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isInputFocused = false
                        }
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
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
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
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
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
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Model selector
                Button {
                    showModelPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)

                        Text(store.defaultModel?.catalogItem.displayName ?? "Select model")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        if let runtime = store.defaultModel?.catalogItem.runtimeType {
                            Text(runtime.label)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(runtime == .mlx ? .orange : AppTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(runtime == .mlx ? Color.orange.opacity(0.12) : AppTheme.panelRaised)
                                .clipShape(Capsule())
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Status pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(liveSearchEnabled ? AppTheme.warning : AppTheme.success)
                        .frame(width: 6, height: 6)
                    Text(liveSearchEnabled ? "Search" : "Offline")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(liveSearchEnabled ? AppTheme.warning : AppTheme.success)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.panel.opacity(0.8))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(AppTheme.hairline, lineWidth: 1)
                )

                if store.settings.voiceModeEnabled, let lastAssistantResponseText, !lastAssistantResponseText.isEmpty {
                    Button {
                        replayLastAssistantResponse()
                    } label: {
                        Image(systemName: voiceController.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(voiceController.isSpeaking ? AppTheme.warning : AppTheme.accent)
                            .padding(8)
                            .background(AppTheme.panel.opacity(0.8))
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(AppTheme.hairline, lineWidth: 1)
                            )
                    }
                }
            }

            // Capability badges + model summary
            if let model = store.defaultModel, !isCompactHeader {
                VStack(spacing: 6) {
                    // Capability badges
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            capabilityBadge(icon: "text.bubble", label: "Chat", active: true, color: AppTheme.accent)

                            capabilityBadge(icon: "eye", label: "Vision", active: model.catalogItem.supportsVision, color: .purple)

                            capabilityBadge(icon: "brain.head.profile", label: "Reasoning", active: model.catalogItem.supportsReasoning, color: .cyan)

                            capabilityBadge(icon: "lightbulb.max", label: "Thinking", active: model.catalogItem.isThinkingModel, color: .yellow)

                            capabilityBadge(icon: "wrench.and.screwdriver", label: "Tools", active: model.catalogItem.supportsToolCalling, color: .green)
                        }
                    }

                    // Model summary
                    Text(model.catalogItem.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, isCompactHeader ? 8 : 10)
        .background(
            AppTheme.background.opacity(0.7)
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
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.06))
                    .frame(width: 100, height: 100)
                Circle()
                    .fill(AppTheme.accent.opacity(0.10))
                    .frame(width: 68, height: 68)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(AppTheme.accent.opacity(0.7))
            }

            VStack(spacing: 8) {
                Text("Start a Conversation")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(store.defaultModel == nil
                     ? "Install a model from the library to begin"
                     : "Ask anything — everything runs on-device")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if store.defaultModel == nil {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab.wrappedValue = 1
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Browse Models")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent.opacity(0.15))
                    .foregroundStyle(AppTheme.accent)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(32)
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
                let searchContext = try await resolveSearchContext(for: trimmedPrompt)
                if let searchContext {
                    let searchMessage = ChatMessage(
                        role: .search,
                        text: "Live Search returned \(searchContext.citations.count) sources.",
                        citations: searchContext.citations
                    )
                    await MainActor.run {
                        store.appendMessage(searchMessage, to: sessionID)
                    }
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

    private func resolveSearchContext(for prompt: String) async throws -> SearchContext? {
        guard liveSearchEnabled || store.settings.useSearchByDefault else { return nil }
        guard let gateway = SearchGatewayFactory.make(settings: store.settings) else { return nil }
        return try await gateway.search(query: prompt)
    }
}
