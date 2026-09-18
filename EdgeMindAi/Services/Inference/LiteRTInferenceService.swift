import Foundation
import OSLog

#if canImport(LiteRTLM) && !targetEnvironment(simulator)
import LiteRTLM

private let liteRTLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "LiteRTRuntime")

private final class LiteRTConversationStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var conversation: Conversation?
    private var task: Task<Void, Never>?
    private var finished = false

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    func setTask(_ task: Task<Void, Never>) {
        lock.withLock {
            self.task = task
        }
    }

    func finish() {
        let retainedConversation: Conversation? = lock.withLock {
            finished = true
            task = nil
            let retainedConversation = conversation
            conversation = nil
            return retainedConversation
        }
        _ = retainedConversation
    }

    func cancel() {
        let state: (Task<Void, Never>?, Conversation?, Bool) = lock.withLock {
            if finished { return (nil, nil, true) }
            finished = true
            let state = (task, conversation, false)
            task = nil
            conversation = nil
            return state
        }

        guard !state.2 else { return }
        state.0?.cancel()
        if let conversation = state.1, conversation.isAlive {
            try? conversation.cancel()
        }
    }
}

actor LiteRTRuntime {
    static let shared = LiteRTRuntime()

    private var activeModelPath: String?
    private var activeMultimodal = false
    private var activeEngine: Engine?

    private func cacheDirectory() throws -> String {
        let directory = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "LiteRTLM", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }

    private func ensureEngine(modelPath: String, multimodal: Bool) async throws -> Engine {
        if activeModelPath != modelPath || activeMultimodal != multimodal || activeEngine == nil {
            unload()
            liteRTLogger.log("Loading LiteRT-LM model at \(modelPath, privacy: .public), multimodal=\(multimodal)")
            let config = try EngineConfig(
                modelPath: modelPath,
                backend: .gpu,
                visionBackend: multimodal ? .cpu(threadCount: 2) : nil,
                audioBackend: nil,
                maxNumTokens: 2048,
                cacheDir: try cacheDirectory()
            )
            let engine = Engine(engineConfig: config)
            try await engine.initialize()
            activeModelPath = modelPath
            activeMultimodal = multimodal
            activeEngine = engine
        }

        guard let activeEngine else {
            throw InferenceServiceError.runtimeUnavailable("LiteRT-LM failed to initialize the model.")
        }
        return activeEngine
    }

    func generateStream(
        modelPath: String,
        systemPrompt: String,
        history: [LiteRTLM.Message],
        message: LiteRTLM.Message,
        multimodal: Bool
    ) async throws -> AsyncThrowingStream<String, Error> {
        let engine = try await ensureEngine(modelPath: modelPath, multimodal: multimodal)
        let sampler = try SamplerConfig(topK: 40, topP: 0.95, temperature: multimodal ? 0.1 : 0.7)
        let config = ConversationConfig(
            systemMessage: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : LiteRTLM.Message(systemPrompt, role: .system),
            initialMessages: history,
            samplerConfig: sampler
        )
        let conversation = try await engine.createConversation(with: config)
        let messageStream = conversation.sendMessageStream(message)

        return AsyncThrowingStream { continuation in
            let streamState = LiteRTConversationStreamState(conversation: conversation)
            let task = Task {
                do {
                    for try await chunk in messageStream {
                        if Task.isCancelled {
                            try? conversation.cancel()
                            break
                        }
                        let text = chunk.toString
                        if !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    streamState.finish()
                    continuation.finish()
                } catch {
                    streamState.finish()
                    continuation.finish(throwing: error)
                }
            }
            streamState.setTask(task)
            continuation.onTermination = { _ in
                streamState.cancel()
            }
        }
    }

    func generate(
        modelPath: String,
        systemPrompt: String,
        history: [LiteRTLM.Message],
        message: LiteRTLM.Message,
        multimodal: Bool
    ) async throws -> String {
        let engine = try await ensureEngine(modelPath: modelPath, multimodal: multimodal)
        let sampler = try SamplerConfig(topK: 40, topP: 0.95, temperature: multimodal ? 0.1 : 0.7)
        let config = ConversationConfig(
            systemMessage: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : LiteRTLM.Message(systemPrompt, role: .system),
            initialMessages: history,
            samplerConfig: sampler
        )
        let conversation = try await engine.createConversation(with: config)
        return try await conversation.sendMessage(message).toString
    }

    func unload() {
        activeEngine = nil
        activeModelPath = nil
        activeMultimodal = false
    }
}
#endif

struct LiteRTInferenceService: InferenceService {
    static let defaultMultimodalStreamTimeout: TimeInterval = 75

    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil,
        settings: AppSettings? = nil
    ) async throws -> ChatMessage {
#if canImport(LiteRTLM) && !targetEnvironment(simulator)
        let modelPath = try Self.modelPath(for: model)
        let turn = Self.budgetedTurn(
            prompt: prompt,
            conversation: conversation,
            model: model,
            imageData: imageData,
            baseSystemPrompt: systemPrompt,
            searchContext: searchContext
        )
        let response = try await LiteRTRuntime.shared.generate(
            modelPath: modelPath,
            systemPrompt: turn.system,
            history: turn.history,
            message: turn.message,
            multimodal: imageData != nil
        )
        return ChatMessage(
            role: .assistant,
            text: response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AssistantResponseFallback.emptyOutput : response,
            citations: searchContext?.citations ?? []
        )
#else
        throw InferenceServiceError.runtimeUnavailable("LiteRT-LM requires a real iOS device. It cannot run in the simulator.")
#endif
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil,
        settings: AppSettings? = nil
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
#if canImport(LiteRTLM) && !targetEnvironment(simulator)
        let modelPath = try Self.modelPath(for: model)
        let turn = Self.budgetedTurn(
            prompt: prompt,
            conversation: conversation,
            model: model,
            imageData: imageData,
            baseSystemPrompt: systemPrompt,
            searchContext: searchContext
        )
        let rawThrowingStream = try await LiteRTRuntime.shared.generateStream(
            modelPath: modelPath,
            systemPrompt: turn.system,
            history: turn.history,
            message: turn.message,
            multimodal: imageData != nil
        )
        let rawStream = AsyncStream<String> { continuation in
            // Cancelling the consumer must cancel this bridge. Without `onTermination`
            // the inner Task kept draining `rawThrowingStream` after Stop, so the model
            // ran to its token cap (heat/battery) and the conversation's own
            // `cancel()` — reachable only from the INNER stream's termination — never
            // fired, leaving the multi-GB engine unloadable on a memory warning.
            let task = Task {
                do {
                    for try await chunk in rawThrowingStream {
                        if Task.isCancelled { break }
                        continuation.yield(chunk)
                    }
                } catch {
                    continuation.yield(Self.friendlyLiteRTError(error))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        let runtimeProfile = RuntimeProfileStore().profile(for: model.catalogItem.id)
            ?? .safeMinimum(catalogID: model.catalogItem.id)
        let processor = StreamProcessor(
            rawStream: rawStream,
            leakTokens: runtimeProfile.knownLeakTokens,
            v2Enabled: settings?.streamProcessorV2Enabled ?? AppSettings.default.streamProcessorV2Enabled,
            hangTimeout: Self.streamHangTimeout(settings: settings, imageData: imageData),
            repetitionNgram: 6,
            repetitionCount: 3,
            activeThinkFormats: Set(runtimeProfile.verifiedThinking.map { [$0] } ?? [])
        )
        return (messageID: UUID(), stream: await processor.process())
#else
        throw InferenceServiceError.runtimeUnavailable("LiteRT-LM requires a real iOS device. It cannot run in the simulator.")
#endif
    }

#if canImport(LiteRTLM) && !targetEnvironment(simulator)
    private static func modelPath(for model: InstalledModel) throws -> String {
        guard let fileURL = model.fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw InferenceServiceError.missingLocalModelFile
        }
        return fileURL.path
    }

    /// Assembles the prompt for one turn and clamps the **total** to the model's
    /// safe context window. LiteRT-LM hard-caps at 2048 tokens and fails the
    /// request above it, so history alone is not enough — the current turn
    /// (which carries inlined document text) and the history are trimmed
    /// together by `InferenceBudget.fitPrompt`.
    private static func budgetedTurn(
        prompt: String,
        conversation: [ChatMessage],
        model: InstalledModel,
        imageData: Data?,
        baseSystemPrompt: String,
        searchContext: SearchContext?
    ) -> (system: String, history: [LiteRTLM.Message], message: LiteRTLM.Message) {
        let system = systemPrompt(base: baseSystemPrompt, searchContext: searchContext)
        let entries = historyEntries(from: conversation, model: model, multimodal: imageData != nil)

        let fitted = InferenceBudget.fitPrompt(
            system: system,
            history: entries.map(\.text),
            current: prompt,
            for: model,
            searchContext: searchContext
        )

        // `fitPrompt` keeps a contiguous suffix, so the surviving count maps
        // straight back onto the role-tagged entries.
        let retained = entries.suffix(fitted.history.count).map(\.message)
        return (system, retained, message(prompt: fitted.current, imageData: imageData))
    }

    private static func historyEntries(
        from conversation: [ChatMessage],
        model: InstalledModel,
        multimodal: Bool
    ) -> [(text: String, message: LiteRTLM.Message)] {
        if multimodal {
            return []
        }

        let maxMessages = InferenceBudget.maxHistoryMessages(for: model, searchContext: nil)
        let maxCharacters = InferenceBudget.maxHistoryCharactersPerMessage(for: model)
        var retained: [(text: String, message: LiteRTLM.Message)] = []

        for message in conversation.reversed() {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !AssistantResponseFallback.shouldSkipInHistory(message) else {
                continue
            }

            let boundedText = InferenceBudget.trimHistoryText(text, maxCharacters: maxCharacters)
            let built: LiteRTLM.Message
            switch message.role {
            case .system:
                built = LiteRTLM.Message(boundedText, role: .system)
            case .user:
                built = LiteRTLM.Message(boundedText, role: .user)
            case .assistant:
                built = LiteRTLM.Message(boundedText, role: .model)
            }
            retained.insert((boundedText, built), at: 0)

            if retained.count >= maxMessages {
                break
            }
        }

        return retained
    }

    private static func message(prompt: String, imageData: Data?) -> LiteRTLM.Message {
        var contents: [LiteRTLM.Content] = []
        if let imageData {
            contents.append(.imageData(imageData))
        }
        contents.append(.text(prompt))
        return LiteRTLM.Message(contents: contents, role: .user)
    }
#endif

    static func streamHangTimeout(settings: AppSettings?, imageData: Data?) -> TimeInterval {
        let configuredTimeout = settings?.inferenceV2Timeout ?? AppSettings.default.inferenceV2Timeout
        guard imageData != nil else { return configuredTimeout }
        return max(configuredTimeout, defaultMultimodalStreamTimeout)
    }

    private static func systemPrompt(base: String, searchContext: SearchContext?) -> String {
        guard let searchContext else { return base }

        // LiteRT previously received ONLY a bullet list of citation titles and URLs —
        // `answer` and `snippets` were dropped, so the model had nothing to ground on
        // (GGUF, MLX and Apple Foundation Models all inject them). Keep it bounded so
        // the result still fits LiteRT's hard 2048-token cap.
        let budgetCharacters = 1_600
        var sections: [String] = []

        if let answer = searchContext.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !answer.isEmpty {
            sections.append("Direct answer from search:\n" + String(answer.prefix(budgetCharacters / 2)))
        }

        let snippetText = searchContext.snippets
            .prefix(4)
            .enumerated()
            .map { "- \($1)" }
            .joined(separator: "\n")
        if !snippetText.isEmpty {
            sections.append("Retrieved snippets:\n" + String(snippetText.prefix(budgetCharacters / 2)))
        }

        if !searchContext.citations.isEmpty {
            let sources = searchContext.citations
                .prefix(5)
                .map { "- \($0.title): \($0.url.absoluteString)" }
                .joined(separator: "\n")
            sections.append("Sources:\n" + sources)
        }

        guard !sections.isEmpty else { return base }
        return """
        \(base)

        Use the retrieved information below when it is relevant, and cite the source titles.

        \(sections.joined(separator: "\n\n"))
        """
    }

    private static func friendlyLiteRTError(_ error: Error) -> String {
        let description = error.localizedDescription
        if description.lowercased().contains("memory") {
            return "LiteRT-LM ran out of device memory while processing this request. Try a shorter chat or restart the app and retry."
        }
        return "LiteRT-LM runtime error: \(description)"
    }
}
