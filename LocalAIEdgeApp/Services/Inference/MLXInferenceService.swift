import CoreImage
import Foundation
import OSLog

#if canImport(MLXLLM) && !targetEnvironment(simulator)
import Hub
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

private let mlxLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "MLXRuntime")

actor MLXRuntime {
    static let shared = MLXRuntime()

    private var activeModelID: String?
    private var activeContainer: ModelContainer?
    private var activeIsVision: Bool = false

    private func ensureModel(_ modelID: String, isVision: Bool) async throws -> ModelContainer {
        if activeModelID != modelID || activeContainer == nil || activeIsVision != isVision {
            // Unload previous model first to free GPU memory before loading new one
            if activeContainer != nil {
                mlxLogger.log("Unloading previous model before loading new one")
                unload()
                Memory.clearCache()
            }

            mlxLogger.log("Loading MLX model: \(modelID, privacy: .public) (vision: \(isVision))")
            Memory.cacheLimit = 256 * 1024 * 1024
            let configuration = ModelConfiguration(id: modelID)
            if isVision {
                activeContainer = try await VLMModelFactory.shared.loadContainer(configuration: configuration) { progress in
                    mlxLogger.log("MLX VLM model load progress: \(progress.fractionCompleted)")
                }
            } else {
                activeContainer = try await LLMModelFactory.shared.loadContainer(configuration: configuration) { progress in
                    mlxLogger.log("MLX LLM model load progress: \(progress.fractionCompleted)")
                }
            }
            activeModelID = modelID
            activeIsVision = isVision
        }
        guard let container = activeContainer else {
            throw MLXInferenceError.modelNotLoaded
        }
        return container
    }

    func generate(prompt: String, modelID: String, systemPrompt: String, maxTokens: Int = 1024, imageData: Data? = nil, isVision: Bool = false) async throws -> String {
        let container = try await ensureModel(modelID, isVision: isVision)

        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.7, topP: 0.9)
        var images: [UserInput.Image] = []
        if let imageData, let ciImage = CIImage(data: imageData) {
            images = [.ciImage(ciImage)]
        }
        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(prompt, images: images)
        ]
        let processing: UserInput.Processing = images.isEmpty ? .init() : .init(resize: CGSize(width: 512, height: 512))
        let userInput = UserInput(chat: chat, processing: processing)
        let input = try await container.perform { context in
            try await context.processor.prepare(input: userInput)
        }

        var output = ""
        let stream = try await container.generate(input: input, parameters: parameters)
        for await generation in stream {
            if let chunk = generation.chunk {
                output += chunk
            }
        }

        let finalText = output.trimmingCharacters(in: .whitespacesAndNewlines)
        mlxLogger.log("MLX generation complete: generated \(finalText.count) chars")
        return finalText
    }

    func generateStream(prompt: String, modelID: String, systemPrompt: String, maxTokens: Int = 1024, imageData: Data? = nil, isVision: Bool = false) async throws -> AsyncStream<String> {
        let container = try await ensureModel(modelID, isVision: isVision)

        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.7, topP: 0.9)
        var images: [UserInput.Image] = []
        if let imageData, let ciImage = CIImage(data: imageData) {
            images = [.ciImage(ciImage)]
        }
        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(prompt, images: images)
        ]
        let processing: UserInput.Processing = images.isEmpty ? .init() : .init(resize: CGSize(width: 512, height: 512))
        let userInput = UserInput(chat: chat, processing: processing)
        let input = try await container.perform { context in
            try await context.processor.prepare(input: userInput)
        }

        let mlxStream = try await container.generate(input: input, parameters: parameters)
        return AsyncStream<String> { continuation in
            Task {
                for await generation in mlxStream {
                    if let chunk = generation.chunk {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            }
        }
    }

    func unload() {
        activeContainer = nil
        activeModelID = nil
        activeIsVision = false
    }

    /// Pre-download an MLX model with progress reporting.
    /// Downloads files to disk only — does NOT load weights into GPU memory.
    func preloadModel(_ modelID: String, isVision: Bool = false, progress: @escaping @Sendable (Double) -> Void) async throws {
        mlxLogger.log("Downloading MLX model (no GPU load): \(modelID, privacy: .public)")
        let configuration = ModelConfiguration(id: modelID)
        // Use downloadModel() which only downloads files via hub.snapshot() —
        // does NOT load weights into GPU memory, avoiding OOM on 8GB devices.
        _ = try await downloadModel(hub: defaultHubApi, configuration: configuration) { p in
            let fraction = p.fractionCompleted
            mlxLogger.log("MLX download progress: \(fraction)")
            progress(fraction)
        }
        mlxLogger.log("MLX model downloaded to disk: \(modelID, privacy: .public)")
    }
}

enum MLXInferenceError: LocalizedError {
    case modelNotLoaded
    case simulatorNotSupported

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Failed to load the MLX model."
        case .simulatorNotSupported:
            return "MLX models require a real device with Apple Silicon. They cannot run in the iOS Simulator."
        }
    }
}

struct MLXInferenceService: InferenceService {
    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> ChatMessage {
        guard let mlxModelID = model.catalogItem.mlxModelID else {
            throw InferenceServiceError.missingLocalModelFile
        }

        let isVision = model.catalogItem.supportsVision
        let fullSystemPrompt = Self.buildSystemPrompt(systemPrompt: systemPrompt, searchContext: searchContext)
        let fullPrompt = Self.buildFullPrompt(conversation: conversation, prompt: prompt)

        do {
            let response = try await MLXRuntime.shared.generate(
                prompt: fullPrompt,
                modelID: mlxModelID,
                systemPrompt: fullSystemPrompt,
                maxTokens: isVision ? 512 : 1024,
                imageData: imageData,
                isVision: isVision
            )
            return ChatMessage(
                role: .assistant,
                text: response.isEmpty ? "The model finished without returning text. Try a shorter prompt or another model." : response,
                citations: searchContext?.citations ?? []
            )
        } catch {
            throw InferenceServiceError.runtimeUnavailable(error.localizedDescription)
        }
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> (messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>) {
        guard let mlxModelID = model.catalogItem.mlxModelID else {
            throw InferenceServiceError.missingLocalModelFile
        }

        let isVision = model.catalogItem.supportsVision
        let fullSystemPrompt = Self.buildSystemPrompt(systemPrompt: systemPrompt, searchContext: searchContext)
        let fullPrompt = Self.buildFullPrompt(conversation: conversation, prompt: prompt)

        let messageID = UUID()
        let citations = searchContext?.citations ?? []
        let stream = try await MLXRuntime.shared.generateStream(
            prompt: fullPrompt,
            modelID: mlxModelID,
            systemPrompt: fullSystemPrompt,
            maxTokens: isVision ? 512 : 1024,
            imageData: imageData,
            isVision: isVision
        )
        return (messageID, citations, stream)
    }

    private static func buildSystemPrompt(systemPrompt: String, searchContext: SearchContext?) -> String {
        var result = "\(systemPrompt)\nYou are running locally on-device using MLX on Apple Silicon. Respond directly to the user's question. Do not hallucinate or fabricate information."
        if let searchContext {
            let snippets = searchContext.snippets.prefix(3).enumerated().map { index, snippet in
                let cleaned = stripHTML(snippet)
                let truncated = cleaned.count > 300 ? String(cleaned.prefix(300)) + "..." : cleaned
                return "[\(index + 1)] \(truncated)"
            }.joined(separator: "\n")
            result += "\n\nWeb Search Results — Answer the user's question using these results. Reference sources by number (e.g. [1], [2]) in your answer. If the results don't help, say so.\n\(snippets)"
        }
        return result
    }

    private static func buildFullPrompt(conversation: [ChatMessage], prompt: String) -> String {
        let eligibleMessages = conversation.filter { $0.role != .search }
        let maxPromptTokens = 6800
        let fixedTokens = max(1, prompt.utf8.count / 4) + 200
        let historyBudget = maxPromptTokens - fixedTokens
        var historyLines: [String] = []
        var usedTokens = 0

        for message in eligibleMessages.reversed() {
            let line: String
            switch message.role {
            case .assistant: line = "Assistant: \(message.text)"
            case .user: line = "User: \(message.text)"
            case .system: line = "System: \(message.text)"
            case .search: continue
            }
            let cost = max(1, line.utf8.count / 4)
            if usedTokens + cost > historyBudget { break }
            historyLines.insert(line, at: 0)
            usedTokens += cost
        }

        var fullPrompt = ""
        if !historyLines.isEmpty {
            fullPrompt += historyLines.joined(separator: "\n\n") + "\n\n"
        }
        fullPrompt += prompt
        return fullPrompt
    }

    private static func stripHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

#else

// Stub for simulator / when MLXLLM is not available
enum MLXInferenceError: LocalizedError {
    case simulatorNotSupported

    var errorDescription: String? {
        return "MLX models require a real device with Apple Silicon. They cannot run in the iOS Simulator."
    }
}

struct MLXInferenceService: InferenceService {
    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> ChatMessage {
        throw MLXInferenceError.simulatorNotSupported
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> (messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>) {
        throw MLXInferenceError.simulatorNotSupported
    }
}

#endif
