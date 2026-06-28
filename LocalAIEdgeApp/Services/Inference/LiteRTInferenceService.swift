import Foundation
import OSLog

#if canImport(LiteRTLM) && !targetEnvironment(simulator)
import LiteRTLM

private let liteRTLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "LiteRTRuntime")

actor LiteRTRuntime {
    static let shared = LiteRTRuntime()

    private var activeModelPath: String?
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
        if activeModelPath != modelPath || activeEngine == nil {
            unload()
            liteRTLogger.log("Loading LiteRT-LM model at \(modelPath, privacy: .public)")
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
            Task {
                do {
                    for try await chunk in messageStream {
                        let text = chunk.toString
                        if !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
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
    }
}
#endif

struct LiteRTInferenceService: InferenceService {
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
        let history = Self.history(from: conversation)
        let currentMessage = Self.message(prompt: prompt, imageData: imageData)
        let response = try await LiteRTRuntime.shared.generate(
            modelPath: modelPath,
            systemPrompt: Self.systemPrompt(base: systemPrompt, searchContext: searchContext),
            history: history,
            message: currentMessage,
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
        let history = Self.history(from: conversation)
        let currentMessage = Self.message(prompt: prompt, imageData: imageData)
        let rawThrowingStream = try await LiteRTRuntime.shared.generateStream(
            modelPath: modelPath,
            systemPrompt: Self.systemPrompt(base: systemPrompt, searchContext: searchContext),
            history: history,
            message: currentMessage,
            multimodal: imageData != nil
        )
        let rawStream = AsyncStream<String> { continuation in
            Task {
                do {
                    for try await chunk in rawThrowingStream {
                        continuation.yield(chunk)
                    }
                } catch {
                    continuation.yield(Self.friendlyLiteRTError(error))
                }
                continuation.finish()
            }
        }
        let runtimeProfile = RuntimeProfileStore().profile(for: model.catalogItem.id)
            ?? .safeMinimum(catalogID: model.catalogItem.id)
        let processor = StreamProcessor(
            rawStream: rawStream,
            leakTokens: runtimeProfile.knownLeakTokens,
            v2Enabled: settings?.streamProcessorV2Enabled ?? AppSettings.default.streamProcessorV2Enabled,
            hangTimeout: settings?.inferenceV2Timeout ?? AppSettings.default.inferenceV2Timeout,
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

    private static func history(from conversation: [ChatMessage]) -> [LiteRTLM.Message] {
        conversation.compactMap { message in
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !AssistantResponseFallback.shouldSkipInHistory(message) else {
                return nil
            }

            switch message.role {
            case .system:
                return LiteRTLM.Message(text, role: .system)
            case .user:
                return LiteRTLM.Message(text, role: .user)
            case .assistant:
                return LiteRTLM.Message(text, role: .model)
            }
        }
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

    private static func systemPrompt(base: String, searchContext: SearchContext?) -> String {
        guard let searchContext else { return base }
        let sources = searchContext.citations
            .map { "- \($0.title): \($0.url.absoluteString)" }
            .joined(separator: "\n")
        return """
        \(base)

        Use these retrieved sources when they are relevant:
        \(sources)
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
