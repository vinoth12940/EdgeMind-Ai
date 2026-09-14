import Foundation
import Observation
import OSLog
import UIKit

let chatEngineLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "ChatTurnEngine")

struct TurnRequest {
    enum Target {
        /// Append the user message and a new assistant answer (default).
        case newMessage
        /// Replace the answer of `assistantMessageID` with a new version. The
        /// prompt is re-derived from the preceding user message; `model`
        /// overrides the default model for this turn only.
        case regenerate(assistantMessageID: UUID, model: InstalledModel?)
    }

    let sessionID: UUID
    let prompt: String
    let attachments: [ChatAttachment]
    /// Raw attached image; the engine encodes it with `encodedAttachmentData(from:model:)`.
    let image: UIImage?
    let liveSearchEnabled: Bool
    let target: Target

    init(
        sessionID: UUID,
        prompt: String,
        attachments: [ChatAttachment],
        image: UIImage?,
        liveSearchEnabled: Bool,
        target: Target = .newMessage
    ) {
        self.sessionID = sessionID
        self.prompt = prompt
        self.attachments = attachments
        self.image = image
        self.liveSearchEnabled = liveSearchEnabled
        self.target = target
    }
}

@MainActor
@Observable
final class ChatTurnEngine {
    struct Dependencies {
        var resolveModel: @MainActor (AppStateStore) -> InstalledModel?
        var serviceForModel: @MainActor (InstalledModel) -> InferenceService
        var prepareRuntime: (ModelCatalogItem.RuntimeType) async -> Void
        var releaseAllRuntimes: () async -> Void
        /// (model, hasImage) -> blocking message, or nil to proceed.
        var memoryGuardMessage: @MainActor (InstalledModel, Bool) -> String?
        var idleReleaseDelay: Duration
        /// Saved personal memories. Nil in tests and headless contexts without one.
        var memoryStore: MemoryStore?
    }

    private(set) var isGenerating = false
    /// Set by the view that owns the voice controller.
    @ObservationIgnored var speaker: ((String, AppSettings) -> Void)?

    @ObservationIgnored let store: AppStateStore
    @ObservationIgnored let dependencies: Dependencies
    @ObservationIgnored let profileStore = RuntimeProfileStore()
    @ObservationIgnored let streamUpdateInterval: Duration = .milliseconds(80)

    @ObservationIgnored private var generationTask: Task<Void, Never>?
    /// The most recent turn's task. Unlike `generationTask`, `stop()` does not
    /// clear it, so `waitUntilIdle()` can await the cancelled turn's tail.
    @ObservationIgnored private var lastTurnTask: Task<Void, Never>?
    @ObservationIgnored private var activeGenerationID: UUID?
    @ObservationIgnored private var interruptionReason: GenerationInterruptionReason?
    @ObservationIgnored private var idleRuntimeReleaseTask: Task<Void, Never>?
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?

    init(store: AppStateStore, dependencies: Dependencies) {
        self.store = store
        self.dependencies = dependencies
    }

    func resolved(for model: InstalledModel) -> ResolvedModel {
        ModelRuntimeResolver.resolve(catalog: model.catalogItem, store: profileStore)
    }

    func currentInterruptionNotice() -> String {
        (interruptionReason ?? .user).notice
    }

    /// Test hook: waits for the in-flight turn (if any) to complete.
    func waitUntilIdle() async {
        await lastTurnTask?.value
    }
}

enum GenerationInterruptionReason {
    case user
    case memoryWarning

    var notice: String {
        switch self {
        case .user:
            return "Response stopped by user"
        case .memoryWarning:
            return "Your device needed memory — response was interrupted"
        }
    }
}

// MARK: - Live dependencies

extension ChatTurnEngine {
    /// Holds one service per runtime so instances persist across turns.
    private final class LiveServices {
        let gguf: InferenceService = LocalLlamaInferenceService()
        let mlx: InferenceService = MLXInferenceService()
        let liteRT: InferenceService = LiteRTInferenceService()
        let appleFoundation: InferenceService = AppleFoundationInferenceService()
    }
}

extension ChatTurnEngine.Dependencies {
    /// Production dependencies: the real runtimes, the real memory coordinator,
    /// and the 90-second idle release.
    static func live(memoryStore: MemoryStore? = nil) -> Self {
        let services = ChatTurnEngine.LiveServices()
        return Self(
            resolveModel: { $0.defaultModel },
            serviceForModel: { model in
                switch model.catalogItem.runtimeType {
                case .gguf:
                    return services.gguf
                case .mlx:
                    return services.mlx
                case .liteRTLM:
                    return services.liteRT
                case .foundationModels:
                    return services.appleFoundation
                }
            },
            prepareRuntime: { await RuntimeMemoryCoordinator.prepareForRuntime($0) },
            releaseAllRuntimes: { await RuntimeMemoryCoordinator.releaseAll() },
            memoryGuardMessage: { model, hasImage in
                if let headroomAlert = AvailableMemoryGuard.checkMemoryHeadroom(for: model.catalogItem, isVision: hasImage) {
                    return headroomAlert
                }

                let tier = DeviceTier.current()
                // If the current device tier meets or exceeds the model's minimum tier requirement,
                // do not block execution with the memory guard.
                guard tier < model.catalogItem.minimumTier else { return nil }

                let estimatedGB = model.catalogItem.estimatedResidentGB(contextTokens: tier.safeContextTokens)
                guard estimatedGB > tier.jetsamSoftLimitGB else { return nil }

                return "\(model.catalogItem.displayName) is above the safe memory budget for this device tier (\(String(format: "%.1f", estimatedGB)) GB estimated vs \(String(format: "%.1f", tier.jetsamSoftLimitGB)) GB safe). Pick a smaller model to avoid an iOS memory kill."
            },
            idleReleaseDelay: .seconds(90),
            memoryStore: memoryStore
        )
    }
}

// MARK: - Lifecycle

extension ChatTurnEngine {
    func stop() {
        interruptionReason = .user
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        isGenerating = false
        scheduleIdleRuntimeRelease()
    }

    func handleMemoryWarning() {
        guard isGenerating || generationTask != nil else {
            Task { await dependencies.releaseAllRuntimes() }
            return
        }

        interruptionReason = .memoryWarning
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        isGenerating = false

        if let sessionID = store.selectedSession?.id {
            store.appendMessage(
                ChatMessage(role: .system, text: GenerationInterruptionReason.memoryWarning.notice),
                to: sessionID
            )
        }

        Task { await dependencies.releaseAllRuntimes() }
    }

    /// Releases every runtime's memory. The view calls this when the app
    /// backgrounds while no turn is in flight.
    func releaseRuntimes() async {
        await dependencies.releaseAllRuntimes()
    }

    /// Eagerly loads the selected model's weights when the user picks it from
    /// the model picker, so the first message send doesn't pay the load cost.
    /// Routed through `prepareRuntime` so competing runtimes are evicted
    /// (memory invariant preserved). The task is cancelled if the user picks
    /// another model before load completes.
    func prewarmDefaultModel() {
        prewarmTask?.cancel()
        guard let model = dependencies.resolveModel(store), model.catalogItem.runtimeType == .gguf else {
            // Only GGUF pre-warms here — MLX/LiteRT load lazily inside their
            // services and FoundationModels has no weights to load. GGUF is
            // also the only path testable in the simulator.
            return
        }
        guard let modelPath = model.localPath else { return }

        prewarmTask = Task {
            await dependencies.prepareRuntime(model.catalogItem.runtimeType)
            if Task.isCancelled { return }
            // `generate(prompt:using:maxGeneratedTokens:)` with an empty prompt
            // triggers `ensureContext` (the actual weight load) without running
            // a full generation. A subsequent real send reuses the loaded
            // context because the cap is now a per-call parameter (0.3.0).
            do {
                _ = try await LocalLlamaRuntime.shared.generate(prompt: " ", using: modelPath, maxGeneratedTokens: 1)
                chatEngineLogger.log("Pre-warmed GGUF model: \(model.catalogItem.displayName, privacy: .public)")
            } catch {
                chatEngineLogger.log("Pre-warm skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func scheduleIdleRuntimeRelease() {
        idleRuntimeReleaseTask?.cancel()
        let delay = dependencies.idleReleaseDelay
        idleRuntimeReleaseTask = Task {
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }
            await dependencies.releaseAllRuntimes()
        }
    }

    func finishGenerationIfCurrent(_ taskID: UUID) {
        guard activeGenerationID == taskID else { return }
        isGenerating = false
        generationTask = nil
        activeGenerationID = nil
        interruptionReason = nil
        scheduleIdleRuntimeRelease()
    }
}

// MARK: - Helpers

extension ChatTurnEngine {
    /// The no-model / memory-guard / image-unsupported message `send` would
    /// write for the current default model, or `nil` when the turn can proceed.
    func preflightBlockMessage(hasImage: Bool) -> String? {
        guard let model = dependencies.resolveModel(store) else {
            return InferenceServiceError.noModelInstalled.localizedDescription
        }
        return preflightBlockMessage(model: model, hasImage: hasImage)
    }

    private func preflightBlockMessage(model: InstalledModel, hasImage: Bool) -> String? {
        if let memoryGuardMessage = dependencies.memoryGuardMessage(model, hasImage) {
            return memoryGuardMessage
        }
        if hasImage && !ChatInputCapability.acceptsImage(model, profileStore: profileStore) {
            return ChatInputCapability.imageUnsupportedMessage
        }
        return nil
    }

    func canUseToolLoop(model: InstalledModel, resolved: ResolvedModel, imageData: Data?) -> Bool {
        guard model.catalogItem.supportsToolCalling, resolved.tools != nil else { return false }

        // When an image is present, keep the turn on the vision comprehension
        // path instead of injecting tools which confuse VLMs (e.g. Qwen 3.5 VL emitting search_chats).
        if imageData != nil {
            return false
        }

        return true
    }

    func cleanedDisplayedAssistantText(_ text: String) -> String {
        var cleaned = AssistantResponseSanitizer.clean(text)
        cleaned = cleaned.replacingOccurrences(of: AssistantResponseFallback.emptyOutput, with: "")
        cleaned = cleaned.replacingOccurrences(of: AssistantResponseFallback.emptyOutputAfterThinking, with: "")
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolvedAssistantText(from rawText: String, prompt: String, thinkingSeen: Bool) -> String {
        let finalText = cleanedDisplayedAssistantText(rawText)
        if AssistantResponseFallback.isInstructionEcho(finalText, systemPrompt: store.settings.systemPrompt) {
            return AssistantResponseFallback.instructionEcho
        }
        if finalText.isEmpty || AssistantResponseFallback.isPromptEcho(finalText, prompt: prompt) {
            return AssistantResponseFallback.emptyOutputMessage(thinkingSeen: thinkingSeen)
        }
        return finalText
    }

    func searchAwareAssistantText(
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

    static func encodedAttachmentData(from image: UIImage?, model: InstalledModel) -> Data? {
        guard let image else { return nil }

        let isMLXVision = (model.catalogItem.runtimeType == .mlx || model.catalogItem.runtimeType == .liteRTLM)
            && (model.catalogItem.supportsVision || model.catalogItem.sourceSupportsVision)
        let preparedImage = isMLXVision ? downsampleImage(image, maxDimension: 640) : image
        let maxBytes = isMLXVision ? 320_000 : 700_000
        let qualitySteps: [CGFloat] = [0.75, 0.65, 0.55, 0.45, 0.35, 0.25]
        for quality in qualitySteps {
            guard let data = preparedImage.jpegData(compressionQuality: quality) else { continue }
            if data.count <= maxBytes {
                return data
            }
        }
        return preparedImage.jpegData(compressionQuality: 0.25)
    }

    nonisolated static func downsampleImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Translates a raw inference error into a concise, user-facing message.
    /// Maps known failure modes (missing model file, context init, MLX
    /// unavailable) to actionable copy instead of leaking framework strings.
    static func friendlyInferenceError(_ error: Error, modelName: String) -> String {
        if let inferenceError = error as? InferenceServiceError {
            switch inferenceError {
            case .missingLocalModelFile:
                return "⚠️ The model file for \(modelName) is missing. Try re-downloading it from the Models tab."
            case .runtimeUnavailable(let detail):
                return "⚠️ \(modelName) couldn't start: \(detail)"
            case .noModelInstalled:
                return "⚠️ No model is installed yet. Download one from the Models tab to start chatting."
            }
        }
        return "⚠️ \(modelName) ran into a problem: \(error.localizedDescription)"
    }
}

// MARK: - Send

extension ChatTurnEngine {
    func send(_ request: TurnRequest) {
        guard !isGenerating else { return }

        let sessionID = request.sessionID
        guard let session = store.chatSessions.first(where: { $0.id == sessionID }) else { return }

        var trimmedPrompt = request.prompt
        var currentImage = request.image
        var currentDocuments = request.attachments
        var conversation = session.messages
        var overrideModel: InstalledModel?
        var outputMode: StoreTurnOutput.Mode = .newMessage

        switch request.target {
        case .newMessage:
            break
        case .regenerate(let assistantMessageID, let model):
            // History is everything before the answer being replaced. The prompt
            // and image come from the user message that triggered that answer.
            guard let assistantIndex = session.messages.firstIndex(where: { $0.id == assistantMessageID }),
                  session.messages[assistantIndex].role == .assistant,
                  let userMessage = session.messages[..<assistantIndex].last(where: { $0.role == .user }) else {
                return
            }
            overrideModel = model
            trimmedPrompt = userMessage.text
            currentImage = userMessage.imageData.flatMap(UIImage.init(data:))
            currentDocuments = userMessage.attachments.filter { $0.kind != .image }
            conversation = Array(session.messages[..<assistantIndex])
            outputMode = .regenerate(
                assistantMessageID: assistantMessageID,
                modelName: (model ?? dependencies.resolveModel(store))?.catalogItem.displayName ?? ""
            )
        }

        guard !trimmedPrompt.isEmpty || currentImage != nil || !currentDocuments.isEmpty else { return }
        let output = StoreTurnOutput(store: store, sessionID: sessionID, mode: outputMode)

        guard let model = overrideModel ?? dependencies.resolveModel(store) else {
            output.finish(text: InferenceServiceError.noModelInstalled.localizedDescription, toolActivities: nil, stats: nil, duration: nil)
            return
        }

        if let blockMessage = preflightBlockMessage(model: model, hasImage: currentImage != nil) {
            output.finish(text: blockMessage, toolActivities: nil, stats: nil, duration: nil)
            return
        }

        // Encode image at bounded size to avoid memory spikes during persistence/inference.
        let jpegData = Self.encodedAttachmentData(from: currentImage, model: model)
        let attachments = ([jpegData.map { ChatAttachment.image($0) }].compactMap { $0 } + currentDocuments)
        let documentContext = DocumentExtractionService.promptContext(from: attachments)
        let inferencePrompt = documentContext.isEmpty ? trimmedPrompt : "\(trimmedPrompt)\n\n\(documentContext)"

        let effectiveImageData = ChatVisionContext.inheritedImageData(
            explicitImageData: jpegData,
            prompt: trimmedPrompt,
            conversation: conversation,
            model: model,
            profileStore: profileStore
        )

        // A fresh turn appends its user message; a regenerate keeps the existing
        // one and only replaces the answer.
        if !outputMode.isRegenerate {
            let userMessage = ChatMessage(role: .user, text: trimmedPrompt, attachments: attachments)
            store.appendMessage(userMessage, to: sessionID)
        }

        let raiDecision = ResponsibleAIGuard.evaluate(prompt: trimmedPrompt)
        if raiDecision.isBlocked, let response = raiDecision.response {
            chatEngineLogger.log("RAI guard blocked prompt: \(raiDecision.reason ?? "unknown", privacy: .public)")
            output.finish(text: response, toolActivities: nil, stats: nil, duration: nil)
            return
        }

        isGenerating = true

        let taskID = UUID()
        activeGenerationID = taskID
        interruptionReason = nil

        let task = Task {
            var accumulated = ""
            do {
                idleRuntimeReleaseTask?.cancel()
                idleRuntimeReleaseTask = nil
                await dependencies.prepareRuntime(model.catalogItem.runtimeType)

                let searchContext: SearchContext?
                // Search flow:
                // - liveSearchEnabled/useSearchByDefault arms web search for this turn
                // - current/live/explicit web queries get upfront search
                // - everything else stays local unless the model decides to call web_search
                // Search results are passed into the model prompt; we only fall back
                // to a grounded summary after generation if the model refuses or emits nothing usable.
                let resolvedModel = resolved(for: model)
                let modelCanUseToolLoop = canUseToolLoop(model: model, resolved: resolvedModel, imageData: effectiveImageData)
                let isOpenELM = model.catalogItem.family == .openELM
                let searchConfigured = SearchGatewayFactory.make(settings: store.settings) != nil
                // OpenELM lane: keep fully local/minimal prompt path for stability.
                let searchArmed = effectiveImageData == nil && !isOpenELM && (request.liveSearchEnabled || store.settings.useSearchByDefault)
                let promptNeedsLocalTool = UpfrontToolDetector.canHandleLocally(prompt: trimmedPrompt)
                let promptNeedsSearch = !promptNeedsLocalTool
                    && SearchResultFallbackComposer.shouldRunUpfrontSearch(trimmedPrompt)

                if searchArmed && !searchConfigured && (request.liveSearchEnabled || promptNeedsSearch) {
                    output.appendNotice(
                        "⚠️ Web Search is active, but no search API key is configured. Please go to **Settings** to add your Tavily, Brave, or Serper API key to retrieve live results."
                    )
                }

                // If the model natively supports tool calling, we let the model decide to search (think first, then search).
                // We only perform an upfront search as a fallback for models that do NOT support tool calling.
                let shouldUpfrontSearch = searchConfigured
                    && searchArmed
                    && !modelCanUseToolLoop
                    && promptNeedsSearch
                if shouldUpfrontSearch,
                   let gateway = SearchGatewayFactory.make(settings: store.settings) {
                    do {
                        let refinedQuery = SearchQueryRefiner.refine(trimmedPrompt, conversation: conversation)
                        searchContext = try await gateway.search(query: refinedQuery)
                    } catch {
                        output.appendNotice("⚠️ Search failed: \(error.localizedDescription)")
                        searchContext = nil
                    }
                } else {
                    searchContext = nil
                }

                // Inject tool definitions when the model supports the tool loop and no
                // upfront search results are available. The registry renders the `# Tools`
                // section from whichever tools are available this turn (gated by config +
                // attachments + history), generalizing the old web_search-only definition.
                var systemPromptForInference = store.settings.systemPrompt
                var usedMemoryCount = 0
                if store.settings.memoryEnabled, let memoryStore = dependencies.memoryStore {
                    let memorySection = memoryStore.promptSection(for: model)
                    if !memorySection.text.isEmpty {
                        systemPromptForInference += "\n\n" + memorySection.text
                        usedMemoryCount = memorySection.includedCount
                        chatEngineLogger.log("Memory section injected: \(memorySection.includedCount) items")
                    }
                }
                let toolContext = ToolContext(
                    settings: store.settings,
                    conversation: conversation,
                    chatSessions: store.chatSessions,
                    attachedDocuments: attachments,
                    installedModel: model
                )
                let availableTools = ToolRegistry.availableTools(context: toolContext)
                if modelCanUseToolLoop && searchContext == nil && !availableTools.isEmpty {
                    let section = ToolRegistry.renderPromptSection(for: availableTools)
                    systemPromptForInference += section
                    chatEngineLogger.log("Tool definitions injected: \(availableTools.map { $0.name }.joined(separator: ", "), privacy: .public)")
                } else if searchContext != nil {
                    chatEngineLogger.log("Upfront search provided results — tool definition skipped to save context window")
                } else if !modelCanUseToolLoop && effectiveImageData == nil {
                    // Non-tool models can't emit <tool_call> blocks, so the agentic loop
                    // won't fire. Instead, detect local-tool intent UPFRONT (time, device,
                    // battery, calculate) and inject the result into the system prompt.
                    // The model just reads it and answers. Mirrors the upfront web_search path.
                    // When an image is attached, skip upfront tools so questions like "what
                    // device is this in the picture" are answered by the vision model.
                    let upfront = await UpfrontToolDetector.detectAndRun(
                        prompt: trimmedPrompt,
                        context: toolContext
                    )
                    if !upfront.isEmpty {
                        if let directAnswer = UpfrontToolDetector.directAnswer(for: upfront) {
                            output.finish(
                                text: directAnswer,
                                toolActivities: upfront.map { Self.toolActivity(from: $0, model: model) },
                                stats: nil,
                                duration: nil
                            )
                            finishGenerationIfCurrent(taskID)
                            return
                        }
                        let injection = UpfrontToolDetector.renderInjection(for: upfront)
                        systemPromptForInference += injection
                        chatEngineLogger.log("Upfront local tools injected for non-tool model: \(upfront.map { $0.toolName }.joined(separator: ", "), privacy: .public)")
                    } else {
                        chatEngineLogger.log("Non-tool model, no local-tool intent detected")
                    }
                } else if effectiveImageData != nil {
                    chatEngineLogger.log("Image present — tool definitions and upfront tools skipped for vision turn")
                } else {
                    chatEngineLogger.log("No tools available this turn — tool definition NOT injected")
                }

                // Create a placeholder assistant message for streaming
                let service = dependencies.serviceForModel(model)
                let pendingCitations = searchContext?.citations ?? []
                let (messageID, stream) = try await service.generateStream(
                    prompt: inferencePrompt,
                    model: model,
                    conversation: conversation,
                    searchContext: searchContext,
                    systemPrompt: systemPromptForInference,
                    imageData: effectiveImageData,
                    settings: store.settings
                )

                output.beginAnswer(messageID: messageID, citations: pendingCitations)
                if usedMemoryCount > 0 {
                    output.setMemoryCount(usedMemoryCount)
                }

                var thinkingAccumulated = ""
                var stoppedByUser = false
                var capturedStats: GenerationStats?
                let clock = ContinuousClock()
                var lastFlush = clock.now

                let streamStartTime = Date()
                for await event in stream {
                    if Task.isCancelled {
                        let interruptionNotice = currentInterruptionNotice()
                        accumulated += "\n\n*(\(interruptionNotice))*"
                        stoppedByUser = true
                        output.update(text: accumulated, persist: true)
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
                            output.update(text: accumulated, persist: false)
                        }

                    case .thinkingDelta(let chunk):
                        thinkingAccumulated += chunk
                        output.update(thinking: thinkingAccumulated, duration: nil, persist: false)

                    case .thinkingDone(let duration):
                        output.update(thinking: thinkingAccumulated, duration: duration, persist: true)

                    case .toolCall(let name, let argsJSON):
                        chatEngineLogger.log("StreamProcessor yielded .toolCall: name=\(name, privacy: .public) argsLen=\(argsJSON.count)")
                        guard modelCanUseToolLoop else {
                            chatEngineLogger.log("Ignoring tool call: model is not tool-verified")
                            break
                        }
                        // Multi-tool, multi-step dispatch via the registry. This loop
                        // runs the tool, shows a status message, then re-invokes inference
                        // with the tool result appended to the system prompt. Bounded by
                        // ToolRegistry.maxIterations to cap latency. web_search keeps its
                        // structured searchContext render path; other tools append plain text.
                        let loopOutcome = await runToolLoop(
                            toolName: name,
                            argsJSON: argsJSON,
                            output: output,
                            model: model,
                            service: service,
                            conversation: conversation,
                            inferencePrompt: inferencePrompt,
                            trimmedPrompt: trimmedPrompt,
                            effectiveImageData: effectiveImageData,
                            baseSystemPrompt: store.settings.systemPrompt,
                            toolContext: toolContext,
                            taskID: taskID,
                            clock: clock,
                            lastFlush: lastFlush
                        )
                        accumulated = loopOutcome.finalText
                        if loopOutcome.finished {
                            finishGenerationIfCurrent(taskID)
                            return
                        }
                        // Loop indicated "continue consuming" — but the for-await over the
                        // original stream has already terminated (tool call ends the stream),
                        // so we fall through to the post-stream path. The multi-step state is
                        // carried via accumulated/toolResults appended below in runToolLoop.

                    case .done(let stats):
                        capturedStats = stats
                    }
                }

                // Cancelling the task ends `for await` over an AsyncStream without
                // delivering another event, so the in-loop check above is usually
                // skipped. Mark the stop here so no fallback search/retry or voice
                // playback runs after the user pressed Stop.
                if Task.isCancelled && !stoppedByUser {
                    let interruptionNotice = currentInterruptionNotice()
                    accumulated += "\n\n*(\(interruptionNotice))*"
                    stoppedByUser = true
                    output.update(text: accumulated, persist: true)
                }

                // ── Post-stream tool call fallback ──────────────────────
                // If StreamProcessor missed a <tool_call> block (e.g. tag split
                // across token boundaries), detect it in the accumulated text.
                chatEngineLogger.log("Stream ended. accumulated length=\(accumulated.count), checking for missed tool calls…")
                if accumulated.lowercased().contains("<tool_call>") || accumulated.lowercased().contains("<|tool_call>") {
                    chatEngineLogger.log("Post-stream: raw text contains tool_call tag")
                }
                if !stoppedByUser,
                   modelCanUseToolLoop,
                   let query = Self.extractToolCallQuery(from: accumulated),
                   SearchGatewayFactory.make(settings: store.settings) != nil {
                    chatEngineLogger.log("Post-stream fallback FIRED — query: \(query, privacy: .private)")

                    let refinedQuery = SearchQueryRefiner.refine(query, conversation: conversation)
                    let runningActivity = Self.toolActivity(
                        name: "web_search",
                        output: refinedQuery,
                        model: model,
                        status: .running
                    )
                    output.update(text: "", persist: false)
                    output.setToolActivities([runningActivity], persist: false)

                    var agenticSearchContext: SearchContext? = nil
                    if let gateway = SearchGatewayFactory.make(settings: store.settings) {
                        chatEngineLogger.log("Post-stream: calling search gateway…")
                        do {
                            agenticSearchContext = try await gateway.search(query: refinedQuery)
                            chatEngineLogger.log("Post-stream: search returned \(agenticSearchContext?.snippets.count ?? 0) snippets")
                            let completed = ToolResult(
                                toolName: "web_search",
                                output: agenticSearchContext?.answer ?? "Found \(agenticSearchContext?.citations.count ?? 0) sources.",
                                citations: agenticSearchContext?.citations ?? [],
                                searchContext: agenticSearchContext
                            )
                            output.setToolActivities([Self.toolActivity(from: completed, model: model)], persist: true)
                            output.setCitations(agenticSearchContext?.citations ?? [])
                        } catch {
                            chatEngineLogger.log("Post-stream: search error: \(error.localizedDescription, privacy: .public)")
                            output.appendNotice("⚠️ Search failed: \(error.localizedDescription)")
                        }
                    } else {
                        chatEngineLogger.log("Post-stream: no search gateway available")
                    }
                    if agenticSearchContext == nil {
                        output.appendNotice("⚠️ Search unavailable — answering from local knowledge.")
                    }

                    let newPendingCitations = agenticSearchContext?.citations ?? []
                    output.setCitations(newPendingCitations)
                    let (_, newStream) = try await service.generateStream(
                        prompt: inferencePrompt,
                        model: model,
                        conversation: conversation,
                        searchContext: agenticSearchContext,
                        systemPrompt: store.settings.systemPrompt,
                        imageData: effectiveImageData,
                        settings: store.settings
                    )

                    (accumulated, thinkingAccumulated) = await consumeFollowupStream(
                        newStream,
                        output: output,
                        clock: clock,
                        lastFlush: lastFlush
                    )
                    let finalText2 = searchAwareAssistantText(
                        from: accumulated,
                        prompt: trimmedPrompt,
                        thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        searchContext: agenticSearchContext
                    )
                    output.finish(text: finalText2, toolActivities: nil, stats: nil, duration: nil)
                    finishGenerationIfCurrent(taskID)
                    return
                }

                // Sanitize the final text — this is what gets stored in conversation history,
                // so template tokens must be stripped to prevent feedback loops on next turn.
                chatEngineLogger.log("Raw accumulated text (\(accumulated.count) chars): \(accumulated.prefix(500), privacy: .private)")
                let finalText = resolvedAssistantText(
                    from: accumulated,
                    prompt: trimmedPrompt,
                    thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                chatEngineLogger.log("Resolved final text (\(finalText.count) chars): \(finalText.prefix(300), privacy: .private)")

                // OpenELM-specific retry path: if the first pass echoed instructions,
                // retry once with an ultra-minimal system prompt and no history/search.
                if !stoppedByUser,
                   model.catalogItem.family == .openELM,
                   (AssistantResponseFallback.isInstructionEchoMessage(finalText)
                        || AssistantResponseFallback.isLikelyOffTopicReply(finalText, prompt: trimmedPrompt)) {
                    chatEngineLogger.log("OpenELM instruction-echo retry triggered.")
                    output.discardAnswer()

                    output.appendNotice("🔄 Retrying OpenELM with minimal prompt…")

                    let (retryMsgID, retryStream) = try await service.generateStream(
                        prompt: inferencePrompt,
                        model: model,
                        conversation: [],
                        searchContext: nil,
                        systemPrompt: "Answer in one short sentence.",
                        imageData: nil,
                        settings: store.settings
                    )
                    output.beginAnswer(messageID: retryMsgID, citations: [])

                    // OpenELM lane: no live UI flushes, no thinking-store updates.
                    (accumulated, thinkingAccumulated) = await consumeFollowupStream(
                        retryStream,
                        output: output,
                        clock: clock,
                        lastFlush: lastFlush,
                        streamsToUI: model.catalogItem.family != .openELM,
                        updatesThinking: false
                    )
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
                    output.finish(text: stabilizedRetryText, toolActivities: nil, stats: nil, duration: nil)
                    finishGenerationIfCurrent(taskID)
                    return
                }

                // ── Search-grounding retry ──────────────────────────
                // Some small models still emit a stock "no real-time access"
                // disclaimer even when fresh web results are already in the prompt.
                // Retry once with a stricter search-grounding prompt and no history.
                if !stoppedByUser,
                   let searchContext,
                   AssistantResponseFallback.isSearchAccessRefusal(finalText) {
                    chatEngineLogger.log("Search-grounding retry triggered after searched response refused live/current access.")
                    output.discardAnswer()

                    output.appendNotice("🔄 Retrying with grounded web results…")

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
                    output.beginAnswer(messageID: retryMsgID, citations: retryCitations)

                    (accumulated, thinkingAccumulated) = await consumeFollowupStream(
                        retryStream,
                        output: output,
                        clock: clock,
                        lastFlush: lastFlush
                    )
                    let retryFinalText = searchAwareAssistantText(
                        from: accumulated,
                        prompt: trimmedPrompt,
                        thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        searchContext: searchContext
                    )
                    output.finish(text: retryFinalText, toolActivities: nil, stats: nil, duration: nil)
                    finishGenerationIfCurrent(taskID)
                    return
                }

                // ── Empty-output fallback ───────────────────────────
                // Two branches depending on whether search was already provided:
                // A) searchContext was provided but model still failed → retry with
                //    simplified prompt (no history, no tool def) to maximize context
                // B) No search context → auto-search and retry
                if !stoppedByUser,
                   AssistantResponseFallback.isEmptyOutputMessage(finalText),
                   effectiveImageData == nil,
                   SearchGatewayFactory.make(settings: store.settings) != nil {

                    if searchContext != nil {
                        // ── Branch A: search was provided, model still produced nothing ──
                        // Retry with a minimal system prompt and no history to give the
                        // model maximum context window for the search results + question.
                        chatEngineLogger.log("Empty-output retry: search context was provided but model produced nothing. Retrying with simplified prompt.")
                        output.discardAnswer()

                        output.appendNotice("🔄 Retrying with simplified prompt…")

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
                        output.beginAnswer(messageID: retryMsgID, citations: retryCitations)

                        (accumulated, thinkingAccumulated) = await consumeFollowupStream(
                            retryStream,
                            output: output,
                            clock: clock,
                            lastFlush: lastFlush
                        )
                        let retryFinalText = searchAwareAssistantText(
                            from: accumulated,
                            prompt: trimmedPrompt,
                            thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            searchContext: searchContext
                        )
                        output.finish(text: retryFinalText, toolActivities: nil, stats: nil, duration: nil)
                        finishGenerationIfCurrent(taskID)
                        return

                    } else if let gateway = SearchGatewayFactory.make(settings: store.settings) {
                        // ── Branch B: no search was done → auto-search and retry ──
                        chatEngineLogger.log("Empty-output auto-search fallback triggered for: \(trimmedPrompt, privacy: .private)")
                        output.discardAnswer()

                        let refinedQuery = SearchQueryRefiner.refine(trimmedPrompt, conversation: conversation)
                        output.appendNotice("🔍 Searching: \(refinedQuery)…")

                        var fallbackSearchContext: SearchContext? = nil
                        do {
                            fallbackSearchContext = try await gateway.search(query: refinedQuery)
                            chatEngineLogger.log("Auto-search fallback returned \(fallbackSearchContext?.snippets.count ?? 0) snippets")
                        } catch {
                            chatEngineLogger.log("Auto-search fallback error: \(error.localizedDescription, privacy: .public)")
                            output.appendNotice("⚠️ Search failed: \(error.localizedDescription)")
                        }

                        if let fallbackSearchContext {
                            let fallbackCitations = fallbackSearchContext.citations
                            let (fbMessageID, fbStream) = try await service.generateStream(
                                prompt: inferencePrompt,
                                model: model,
                                conversation: conversation,
                                searchContext: fallbackSearchContext,
                                systemPrompt: store.settings.systemPrompt,
                                imageData: effectiveImageData,
                                settings: store.settings
                            )
                            output.beginAnswer(messageID: fbMessageID, citations: fallbackCitations)

                            (accumulated, thinkingAccumulated) = await consumeFollowupStream(
                                fbStream,
                                output: output,
                                clock: clock,
                                lastFlush: lastFlush
                            )
                            let fbFinalText = searchAwareAssistantText(
                                from: accumulated,
                                prompt: trimmedPrompt,
                                thinkingSeen: !thinkingAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                searchContext: fallbackSearchContext
                            )
                            output.finish(text: fbFinalText, toolActivities: nil, stats: nil, duration: nil)
                            finishGenerationIfCurrent(taskID)
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

                let streamDuration: Double? = stoppedByUser ? nil : Date().timeIntervalSince(streamStartTime)
                output.finish(
                    text: persistedFinalText,
                    toolActivities: nil,
                    stats: stoppedByUser ? nil : capturedStats,
                    duration: streamDuration
                )

                if !stoppedByUser,
                   store.settings.voiceModeEnabled,
                   store.settings.autoPlayVoiceResponses,
                   !AssistantResponseFallback.isEmptyOutputMessage(persistedFinalText) {
                    speaker?(persistedFinalText, store.settings)
                }

                finishGenerationIfCurrent(taskID)
            } catch {
                if !Task.isCancelled {
                    let friendlyError = Self.friendlyInferenceError(error, modelName: model.catalogItem.displayName)
                    output.appendNotice(friendlyError)
                }
                if !output.isFinished {
                    if output.hasActiveAnswer {
                        let currentText = cleanedDisplayedAssistantText(accumulated)
                        output.finish(
                            text: currentText.isEmpty ? AssistantResponseFallback.emptyOutputMessage(thinkingSeen: false) : currentText,
                            toolActivities: nil,
                            stats: nil,
                            duration: nil
                        )
                    } else {
                        // No answer bubble exists (error before `beginAnswer` or after a
                        // retry lane discarded it): the notice above is the only write.
                        output.finishWithoutAnswer()
                    }
                }
                finishGenerationIfCurrent(taskID)
            }
        }
        generationTask = task
        lastTurnTask = task
    }
}
