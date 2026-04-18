import CoreImage
import Foundation
import OSLog
import UIKit

#if canImport(MLXLLM) && !targetEnvironment(simulator)
import Hub
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

private let mlxLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "MLXRuntime")

/// Builds an authenticated HubApi using the user's stored HF token (if any).
private func authenticatedHubApi() -> HubApi {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    let token = HFTokenManager.token
    return HubApi(downloadBase: base, hfToken: token)
}

actor MLXRuntime {
    static let shared = MLXRuntime()

    private var activeModelID: String?
    private var activeContainer: ModelContainer?
    private var activeIsVision: Bool = false

    func shouldUseVisionFactory(modelID: String, supportsVision: Bool, imageData: Data?) -> Bool {
        guard supportsVision else { return false }
        if imageData != nil { return true }

        let normalizedModelID = modelID.lowercased()
        return normalizedModelID.contains("qwen2.5-vl")
            || normalizedModelID.contains("qwen2-vl")
            || normalizedModelID.contains("qwen3.5")
            || normalizedModelID.contains("qwen3_5")
            || normalizedModelID.contains("-vl-")
    }

    private func ensureModel(_ modelID: String, isVision: Bool) async throws -> ModelContainer {
        if activeModelID != modelID || activeContainer == nil || activeIsVision != isVision {
            // Unload previous model first to free GPU memory before loading new one
            if activeContainer != nil {
                mlxLogger.log("Unloading previous model before loading new one")
                unload()
                GPU.clearCache()
            }

            mlxLogger.log("Loading MLX model: \(modelID, privacy: .public) (vision: \(isVision))")
            // Vision models need more GPU cache for the SigLIP vision tower + image tensors
            GPU.set(cacheLimit: (isVision ? 768 : 512) * 1024 * 1024)
            let hub = authenticatedHubApi()
            let configuration = ModelConfiguration(id: modelID)

            // Retry up to 2 times for transient failures (rate limits, network blips)
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    if isVision {
                        activeContainer = try await VLMModelFactory.shared.loadContainer(hub: hub, configuration: configuration) { progress in
                            mlxLogger.log("MLX VLM model load progress: \(progress.fractionCompleted)")
                        }
                    } else {
                        activeContainer = try await LLMModelFactory.shared.loadContainer(hub: hub, configuration: configuration) { progress in
                            mlxLogger.log("MLX LLM model load progress: \(progress.fractionCompleted)")
                        }
                    }
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    mlxLogger.error("MLX model load attempt \(attempt)/3 failed: \(error.localizedDescription)")
                    if attempt < 3 {
                        // Exponential backoff: 2s, 4s
                        try? await Task.sleep(for: .seconds(2 * attempt))
                    }
                }
            }
            if let lastError {
                throw lastError
            }

            activeModelID = modelID
            activeIsVision = isVision
        }
        guard let container = activeContainer else {
            throw MLXInferenceError.modelNotLoaded
        }
        return container
    }

    func generate(prompt: String, modelID: String, systemPrompt: String, maxTokens: Int = 1024, imageData: Data? = nil, isVision: Bool = false, chatHistory: [Chat.Message] = []) async throws -> String {
        // Clear GPU cache before vision to maximize available memory for the vision encoder
        if isVision {
            GPU.clearCache()
        }
        let container = try await ensureModel(modelID, isVision: isVision)

        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.7, topP: 0.9)
        let images = Self.ciImages(from: imageData)
        // Build proper multi-turn chat: system + history + current user message
        var chat: [Chat.Message] = [.system(systemPrompt)]
        chat.append(contentsOf: chatHistory)
        chat.append(.user(prompt, images: images))
        // Let the VLM processor handle its own image sizing — don't force a resize
        let userInput = UserInput(chat: chat)
        let input = try await container.perform { context in
            try await context.processor.prepare(input: userInput)
        }

        let result: GenerateResult = try await container.perform { context in
            let result: GenerateResult = try MLXLMCommon.generate(
                input: input, parameters: parameters, context: context
            ) { _ in .more }
            return result
        }

        let finalText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        mlxLogger.log("MLX generation complete: generated \(finalText.count) chars")
        return finalText
    }

    /// Convert JPEG Data to CIImage array, handling edge cases robustly.
    private static func ciImages(from imageData: Data?) -> [UserInput.Image] {
        guard let imageData else { return [] }
        // CIImage(data:) can fail on certain JPEG encodings — fall back to UIImage path
        if let ciImage = CIImage(data: imageData) {
            return [.ciImage(ciImage)]
        }
        // Fallback: decode via UIImage → CGImage → CIImage
        if let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage {
            return [.ciImage(CIImage(cgImage: cgImage))]
        }
        return []
    }

    func generateStream(prompt: String, modelID: String, systemPrompt: String, maxTokens: Int = 1024, imageData: Data? = nil, isVision: Bool = false, chatHistory: [Chat.Message] = []) async throws -> AsyncStream<String> {
        // Clear GPU cache before vision to maximize available memory for the vision encoder
        if isVision {
            GPU.clearCache()
        }
        let container = try await ensureModel(modelID, isVision: isVision)

        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.7, topP: 0.9)
        let images = Self.ciImages(from: imageData)
        // Build proper multi-turn chat: system + history + current user message
        var chat: [Chat.Message] = [.system(systemPrompt)]
        chat.append(contentsOf: chatHistory)
        chat.append(.user(prompt, images: images))
        // Let the VLM processor handle its own image sizing — don't force a resize
        let userInput = UserInput(chat: chat)
        let input = try await container.perform { context in
            try await context.processor.prepare(input: userInput)
        }

        let mlxStream: AsyncStream<Generation> = try await container.perform { context in
            try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
        }
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

    /// Delete the on-disk Hub snapshot cache for a downloaded MLX model.
    /// The cache lives at `<CachesDir>/huggingface/hub/models--<org>--<repo>/`.
    func removeModelCache(for modelID: String) {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let dirName = "models--" + modelID.replacingOccurrences(of: "/", with: "--")
        let cacheDir = base
            .appending(path: "huggingface", directoryHint: .isDirectory)
            .appending(path: "hub", directoryHint: .isDirectory)
            .appending(path: dirName, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: cacheDir)
        mlxLogger.log("MLX Hub cache removed for: \(modelID, privacy: .public)")
    }

    /// Pre-download an MLX model with progress reporting.
    /// Downloads files to disk only — does NOT load weights into GPU memory.
    func preloadModel(_ modelID: String, isVision: Bool = false, progress: @escaping @Sendable (Double) -> Void) async throws {
        mlxLogger.log("Downloading MLX model (no GPU load): \(modelID, privacy: .public)")
        let hub = authenticatedHubApi()
        let configuration = ModelConfiguration(id: modelID)
        // Use downloadModel() which only downloads files via hub.snapshot() —
        // does NOT load weights into GPU memory, avoiding OOM on 8GB devices.
        _ = try await downloadModel(hub: hub, configuration: configuration) { p in
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

        let isVision = await MLXRuntime.shared.shouldUseVisionFactory(
            modelID: mlxModelID,
            supportsVision: model.catalogItem.supportsVision,
            imageData: imageData
        )
        let maxGeneratedTokens = InferenceBudget.maxGeneratedTokens(for: model, searchContext: searchContext)
        let fullSystemPrompt = Self.buildSystemPrompt(
            systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
            searchContext: searchContext,
            model: model,
            maxGeneratedTokens: maxGeneratedTokens
        )
        let history = Self.buildChatHistory(
            conversation: conversation,
            model: model,
            searchContext: searchContext,
            maxGeneratedTokens: maxGeneratedTokens
        )

        do {
            let response = try await MLXRuntime.shared.generate(
                prompt: prompt,
                modelID: mlxModelID,
                systemPrompt: fullSystemPrompt,
                maxTokens: maxGeneratedTokens,
                imageData: imageData,
                isVision: isVision,
                chatHistory: history
            )
            return ChatMessage(
                role: .assistant,
                text: response.isEmpty ? AssistantResponseFallback.emptyOutput : response,
                citations: searchContext?.citations ?? []
            )
        } catch {
            throw InferenceServiceError.runtimeUnavailable(Self.friendlyMLXError(error))
        }
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        guard let mlxModelID = model.catalogItem.mlxModelID else {
            throw InferenceServiceError.missingLocalModelFile
        }

        let isVision = await MLXRuntime.shared.shouldUseVisionFactory(
            modelID: mlxModelID,
            supportsVision: model.catalogItem.supportsVision,
            imageData: imageData
        )
        let maxGeneratedTokens = InferenceBudget.maxGeneratedTokens(for: model, searchContext: searchContext)
        let fullSystemPrompt = Self.buildSystemPrompt(
            systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
            searchContext: searchContext,
            model: model,
            maxGeneratedTokens: maxGeneratedTokens
        )
        let history = Self.buildChatHistory(
            conversation: conversation,
            model: model,
            searchContext: searchContext,
            maxGeneratedTokens: maxGeneratedTokens
        )

        let messageID = UUID()
        do {
            let rawStream = try await MLXRuntime.shared.generateStream(
                prompt: prompt,
                modelID: mlxModelID,
                systemPrompt: fullSystemPrompt,
                maxTokens: maxGeneratedTokens,
                imageData: imageData,
                isVision: isVision,
                chatHistory: history
            )
            let processor = StreamProcessor(rawStream: rawStream)
            return (messageID: messageID, stream: await processor.process())
        } catch {
            throw InferenceServiceError.runtimeUnavailable(Self.friendlyMLXError(error))
        }
    }

    /// Tool definition injection is handled centrally by ChatView to ensure
    /// consistent behavior across GGUF and MLX runtimes and to avoid wasting
    /// context window space with duplicate definitions.
    private func effectiveSystemPrompt(_ base: String, model: InstalledModel) -> String {
        return base
    }

    /// Translate common MLX / Hub download errors into user-friendly messages.
    private static func friendlyMLXError(_ error: Error) -> String {
        let desc = error.localizedDescription
        let nsError = error as NSError

        // HuggingFace rate-limit (HTTP 429)
        if desc.contains("429") || desc.lowercased().contains("rate limit") || desc.lowercased().contains("too many requests") {
            return "HuggingFace rate limit reached. Add your HF token in Settings → HuggingFace to raise the limit, or try again in a few minutes."
        }
        // Auth required / forbidden (HTTP 401/403)
        if desc.contains("401") || desc.contains("403") || desc.lowercased().contains("unauthorized") || desc.lowercased().contains("forbidden") {
            return "HuggingFace authentication failed. Check your HF token in Settings → HuggingFace."
        }
        if desc.lowercased().contains("unsupported model type") {
            return "This model architecture is not supported by the MLX runtime bundled in the app. Install one of the supported catalog models instead."
        }
        // Network / timeout
        if nsError.domain == NSURLErrorDomain {
            return "Network error while loading model. Check your connection and try again."
        }
        // Out of memory
        if desc.lowercased().contains("memory") || desc.lowercased().contains("oom") {
            return "Not enough memory to load this model. Try a smaller model or close other apps."
        }
        return desc
    }

    private static func buildSystemPrompt(
        systemPrompt: String,
        searchContext: SearchContext?,
        model: InstalledModel,
        maxGeneratedTokens: Int
    ) -> String {
        var result = "\(systemPrompt)\nYou are running locally on-device using MLX on Apple Silicon. Respond directly to the user's question. Do not hallucinate or fabricate information."
        if let searchContext {
            var parts: [String] = []
            let totalBudget = InferenceBudget.mlxSearchBudgetCharacters(for: model, maxGeneratedTokens: maxGeneratedTokens)

            // 1. Present the pre-summarized answer prominently (if available)
            if let answer = searchContext.answer, !answer.isEmpty {
                let cleanAnswer = stripHTML(answer)
                let answerCap = min(6_000, max(3_000, totalBudget / 3))
                let cappedAnswer = cleanAnswer.count > answerCap ? String(cleanAnswer.prefix(answerCap)) + "..." : cleanAnswer
                parts.append("DIRECT ANSWER: \(cappedAnswer)")
            }

            // 2. Supporting source snippets with keyword relevance extraction
            let answerBudget = searchContext.answer != nil ? min(6_000, max(3_000, totalBudget / 3)) : 0
            let snippetBudget = totalBudget - answerBudget
            let snippetCount = min(5, searchContext.snippets.count)
            let perSnippetLimit = snippetCount > 0 ? snippetBudget / snippetCount : 3000
            let queryKeywords = extractKeywords(from: searchContext.query)

            let sourceLines = searchContext.snippets.prefix(5).enumerated().map { index, snippet -> String in
                let cleaned = stripHTML(snippet)
                let relevant = extractRelevantContent(from: cleaned, keywords: queryKeywords, limit: perSnippetLimit)
                return "[\(index + 1)] \(relevant)"
            }
            parts.append("SOURCES:\n" + sourceLines.joined(separator: "\n"))

            result += "\n\n" + parts.joined(separator: "\n\n") + "\n\nINSTRUCTIONS: Answer the user's question using the information above. If a DIRECT ANSWER is provided, use it as your primary source and expand with details from SOURCES. Be specific and detailed.\n\(SearchGroundingGuidance.instructions)"
        }
        return result
    }

    /// Extract keywords from a search query for relevance matching.
    private static func extractKeywords(from query: String) -> [String] {
        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "in", "on", "at",
                                       "to", "for", "of", "with", "by", "from", "and", "or", "not",
                                       "what", "who", "how", "when", "where", "which", "that", "this",
                                       "do", "does", "did", "will", "can", "could", "would", "should",
                                       "have", "has", "had", "be", "been", "being", "it", "its", "me",
                                       "my", "give", "get", "show", "tell", "full", "all", "about"]
        return query.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    /// Extract paragraphs/sentences from long content that match query keywords.
    private static func extractRelevantContent(from text: String, keywords: [String], limit: Int) -> String {
        guard text.count > limit else { return text }

        let paragraphs = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 30 }

        guard !paragraphs.isEmpty, !keywords.isEmpty else {
            return String(text.prefix(limit)) + "..."
        }

        let scored = paragraphs.map { para -> (String, Int) in
            let lower = para.lowercased()
            let score = keywords.reduce(0) { sum, kw in sum + (lower.contains(kw) ? 1 : 0) }
            return (para, score)
        }
        .sorted { $0.1 > $1.1 }

        var result = ""
        for (para, score) in scored {
            if score == 0 && result.count > limit / 3 { break }
            if result.count + para.count + 1 > limit { break }
            result += (result.isEmpty ? "" : " ") + para
        }

        if result.isEmpty {
            return String(text.prefix(limit)) + "..."
        }
        return result
    }

    /// Build structured multi-turn chat history for MLX chat template application.
    /// Conversation is the prior history — the current user prompt is NOT included here;
    /// it is appended separately in MLXRuntime (where images can also be attached).
    /// Trims oldest turns first when history exceeds the token budget.
    private static func buildChatHistory(
        conversation: [ChatMessage],
        model: InstalledModel,
        searchContext: SearchContext?,
        maxGeneratedTokens: Int
    ) -> [Chat.Message] {
        let historyBudget = InferenceBudget.mlxHistoryBudget(
            for: model,
            searchContext: searchContext,
            maxGeneratedTokens: maxGeneratedTokens
        )
        var turns: [Chat.Message] = []
        var usedTokens = 0

        for message in conversation.reversed() {
            if AssistantResponseFallback.shouldSkipInHistory(message) {
                continue
            }
            switch message.role {
            case .user, .assistant: break
            default: continue  // skip system/search messages
            }
            let cost = max(1, message.text.utf8.count / 4)
            if usedTokens + cost > historyBudget { break }
            switch message.role {
            case .assistant: turns.insert(.assistant(message.text), at: 0)
            case .user:      turns.insert(.user(message.text), at: 0)
            default:         break
            }
            usedTokens += cost
        }
        return turns
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
    case runtimeUnavailable

    var errorDescription: String? {
        return "MLX runtime is not available. Ensure the MLX Swift packages are linked in the build target."
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
        throw MLXInferenceError.runtimeUnavailable
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        throw MLXInferenceError.runtimeUnavailable
    }
}

#endif
