import CoreImage
import Foundation
import ImageIO
import OSLog
import UIKit

#if canImport(MLXLLM) && !targetEnvironment(simulator)
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers

private let mlxLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "MLXRuntime")

/// Builds an authenticated Hugging Face Hub client using the user's stored HF token (if any).
private func authenticatedHubClient() -> HubClient {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    let cache = base.map { HubCache(cacheDirectory: $0.appending(path: "huggingface")) } ?? HubCache.default
    let token = HFTokenManager.token
    return HubClient(host: URL(string: "https://huggingface.co")!, bearerToken: token, cache: cache)
}

private enum HuggingFaceDownloaderError: LocalizedError {
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            return "Invalid Hugging Face repository ID: \(id)"
        }
    }
}

private let mlxSnapshotFilePatterns = [
    "*.safetensors",
    "*.json",
    "*.jinja",
    "*.model",
    "*.txt",
    "*.tiktoken"
]

private struct HuggingFaceDownloader: MLXLMCommon.Downloader {
    private let upstream: HubClient

    init(_ upstream: HubClient) {
        self.upstream = upstream
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = HuggingFace.Repo.ID(rawValue: id) else {
            throw HuggingFaceDownloaderError.invalidRepositoryID(id)
        }
        var lastError: (any Error)?
        for attempt in 1...3 {
            do {
                return try await upstream.downloadSnapshot(
                    of: repoID,
                    revision: revision ?? "main",
                    matching: patterns,
                    maxConcurrentDownloads: 1,
                    progressHandler: { @MainActor progress in
                        progressHandler(progress)
                    }
                )
            } catch {
                lastError = error
                guard attempt < 3, Self.shouldRetry(error) else { throw error }
                try await Task.sleep(for: .seconds(2 * attempt))
            }
        }
        throw lastError ?? CancellationError()
    }

    private static func shouldRetry(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                break
            }
        }
        let description = error.localizedDescription.lowercased()
        return description.contains("network connection was lost")
            || description.contains("timed out")
            || description.contains("internet connection appears to be offline")
    }
}

private struct HuggingFaceTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private struct HuggingFaceTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return HuggingFaceTokenizerBridge(upstream)
    }
}

struct MLXDownloadProgress: Sendable {
    let fraction: Double
    let completedUnitCount: Int64
    let totalUnitCount: Int64

    var statusText: String {
        guard totalUnitCount > 1 else {
            return "Starting download..."
        }

        let completed = ByteCountFormatter.string(fromByteCount: completedUnitCount, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalUnitCount, countStyle: .file)
        return "\(completed) of \(total)"
    }
}

actor MLXRuntime {
    static let shared = MLXRuntime()

    private var activeModelID: String?
    private var activeContainer: ModelContainer?
    private var activeIsVision: Bool = false

    private static var isAuditRun: Bool {
        CommandLine.arguments.contains("--localai-run-model-audit")
    }

    private static func auditLog(_ message: String) {
        guard isAuditRun else { return }
        print("[MODEL_AUDIT_PHASE] \(message)")
        fflush(nil)
    }

    private func isOpenELM(_ modelID: String) -> Bool {
        modelID.lowercased().contains("openelm")
    }

    private func isLFMText(_ modelID: String) -> Bool {
        let normalized = modelID.lowercased()
        return normalized.contains("lfm2.5") && !normalized.contains("-vl-")
    }

    private func gpuCacheLimit(modelID: String, isVision: Bool) -> Int {
        let tier = DeviceTier.current()
        let normalized = modelID.lowercased()
        let isLarge = normalized.contains("4b") || normalized.contains("8b") || normalized.contains("9b")
        let isGemma4Vision = isVision && (normalized.contains("gemma-4") || normalized.contains("gemma4"))

        switch tier {
        case .compact:
            return isVision ? 128 : 128
        case .standard:
            if isGemma4Vision {
                return 128
            }
            if isLarge {
                return isVision ? 192 : 256
            } else {
                return isVision ? 256 : 384
            }
        case .pro:
            if isGemma4Vision {
                return 160
            }
            if isLarge {
                return isVision ? 256 : 512
            } else {
                return isVision ? 384 : 768
            }
        case .ultra:
            if isGemma4Vision {
                return 256
            }
            return isVision ? 512 : 1024
        }
    }

    private struct SamplingPreset {
        let temperature: Float
        let topP: Float
        let repetitionPenalty: Float?
        let repetitionContextSize: Int
    }

    func shouldUseVisionFactory(modelID: String, supportsVision: Bool, imageData: Data?) -> Bool {
        guard supportsVision else { return false }
        return imageData != nil
    }

    private func samplingPreset(for modelID: String, isVision: Bool) -> SamplingPreset {
        if isVision {
            return SamplingPreset(
                temperature: 0.1,
                topP: 0.9,
                repetitionPenalty: nil,
                repetitionContextSize: 0
            )
        }

        let normalized = modelID.lowercased()
        if normalized.contains("openelm") {
            // Apple documents OpenELM generation as plain prompt completion with
            // repetition_penalty=1.2. Avoid chat-template wrapping here.
            return SamplingPreset(
                temperature: 0.0,
                topP: 1.0,
                repetitionPenalty: 1.2,
                repetitionContextSize: 128
            )
        }
        if normalized.contains("lfm2.5") {
            // Liquid recommends low-temperature LFM2.5 generation for stable
            // instruction following. The MLX conversions do not ship a chat
            // template, so deterministic sampling helps the manual template.
            return SamplingPreset(
                temperature: 0.1,
                topP: 0.9,
                repetitionPenalty: 1.05,
                repetitionContextSize: 128
            )
        }
        return SamplingPreset(
            temperature: 0.7,
            topP: 0.9,
            repetitionPenalty: 1.05,
            repetitionContextSize: 64
        )
    }

    private func ensureModel(_ modelID: String, isVision: Bool) async throws -> ModelContainer {
        if activeModelID != modelID || activeContainer == nil || activeIsVision != isVision {
            // Unload previous model first to free GPU memory before loading new one
            if activeContainer != nil {
                mlxLogger.log("Unloading previous model before loading new one")
                unload()
                Memory.clearCache()
            }

            mlxLogger.log("Loading MLX model: \(modelID, privacy: .public) (vision: \(isVision))")
            let limitMB = gpuCacheLimit(modelID: modelID, isVision: isVision)
            mlxLogger.log("Setting MLX GPU cache limit to \(limitMB) MB")
            Memory.cacheLimit = limitMB * 1024 * 1024
            let downloader = HuggingFaceDownloader(authenticatedHubClient())
            let tokenizerLoader = HuggingFaceTokenizerLoader()
            let configuration = ModelConfiguration(id: modelID)

            // Retry up to 2 times for transient failures (rate limits, network blips)
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    if isVision {
                        let modelDirectory = try await downloader.download(
                            id: modelID,
                            revision: "main",
                            matching: mlxSnapshotFilePatterns,
                            useLatest: false
                        ) { progress in
                            mlxLogger.log("MLX VLM model load progress: \(progress.fractionCompleted)")
                        }
                        try Self.patchVisionProcessorConfigIfNeeded(
                            modelID: modelID,
                            modelDirectory: modelDirectory
                        )
                        activeContainer = try await VLMModelFactory.shared.loadContainer(
                            from: modelDirectory,
                            using: tokenizerLoader
                        )
                    } else {
                        activeContainer = try await LLMModelFactory.shared.loadContainer(from: downloader, using: tokenizerLoader, configuration: configuration) { progress in
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
            Memory.clearCache()
        }
        Self.auditLog("ensureModel.start model=\"\(modelID)\" vision=\(isVision)")
        let container = try await ensureModel(modelID, isVision: isVision)
        Self.auditLog("ensureModel.done model=\"\(modelID)\" vision=\(isVision)")

        let sampling = samplingPreset(for: modelID, isVision: isVision)
        let parameters = Self.generateParameters(
            modelID: modelID,
            maxTokens: maxTokens,
            isVision: isVision,
            sampling: sampling
        )
        // Never attach images to non-vision containers.
        let visionMaxPixelSize = Self.visionMaxPixelSize(modelID: modelID, isVision: isVision)
        let images = isVision ? Self.ciImages(from: imageData, maxPixelSize: visionMaxPixelSize) : []
        let userInput: UserInput
        if isOpenELM(modelID) {
            userInput = UserInput(prompt: .text(OpenELMPromptTemplate.render(prompt: prompt)))
        } else if isLFMText(modelID) {
            userInput = UserInput(prompt: .text(LFMPromptTemplate.render(systemPrompt: systemPrompt, prompt: prompt)))
        } else {
            // Build proper multi-turn chat: optional system + history + current user message.
            var chat: [Chat.Message] = []
            if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chat.append(.system(systemPrompt))
            }
            chat.append(contentsOf: chatHistory)
            chat.append(.user(prompt, images: images))
            userInput = UserInput(chat: chat, processing: Self.mediaProcessing(isVision: isVision, maxPixelSize: visionMaxPixelSize))
        }
        Self.auditLog("prepare.start model=\"\(modelID)\" vision=\(isVision) images=\(images.count)")
        let input = try await container.perform { context in
            try await context.processor.prepare(input: userInput)
        }
        Self.auditLog("prepare.done model=\"\(modelID)\" vision=\(isVision)")

        Self.auditLog("generate.start model=\"\(modelID)\" vision=\(isVision) maxTokens=\(maxTokens)")
        let resultText: String = try await container.perform { context in
            let stream = try await Self.generateStreamWithMemoryPolicy(
                input: input,
                parameters: parameters,
                context: context,
                modelID: modelID,
                isVision: isVision
            )
            var text = ""
            for await generation in stream {
                if let chunk = generation.chunk {
                    text += chunk
                }
            }
            return text
        }
        Self.auditLog("generate.done model=\"\(modelID)\" vision=\(isVision)")
        if isVision {
            Memory.clearCache()
        }

        let finalText = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        mlxLogger.log("MLX generation complete: generated \(finalText.count) chars")
        return finalText
    }

    /// Convert JPEG Data to CIImage array, handling edge cases robustly.
    private static func ciImages(from imageData: Data?, maxPixelSize: Int) -> [UserInput.Image] {
        guard let imageData else { return [] }
        return autoreleasepool {
            // Downsample before MLX sees the image. Large VLMs can cross the
            // iOS jetsam line if we hand the processor a 512px image.
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary

            if let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
               let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) {
                return [.ciImage(CIImage(cgImage: cgImage))]
            }
            // Fallback: decode via UIImage → CGImage → CIImage
            if let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage {
                return [.ciImage(CIImage(cgImage: cgImage))]
            }
            return []
        }
    }

    private static func mediaProcessing(isVision: Bool, maxPixelSize: Int) -> UserInput.Processing {
        guard isVision else { return .init() }
        return .init(resize: CGSize(width: maxPixelSize, height: maxPixelSize))
    }

    private static func generateParameters(
        modelID: String,
        maxTokens: Int,
        isVision: Bool,
        sampling: SamplingPreset
    ) -> GenerateParameters {
        let normalized = modelID.lowercased()
        let isGemma4Vision = isVision && (normalized.contains("gemma-4") || normalized.contains("gemma4"))

        return GenerateParameters(
            maxTokens: isGemma4Vision ? min(maxTokens, 16) : maxTokens,
            maxKVSize: isGemma4Vision ? 512 : nil,
            kvBits: isGemma4Vision ? 4 : nil,
            kvGroupSize: 64,
            quantizedKVStart: 0,
            temperature: sampling.temperature,
            topP: sampling.topP,
            repetitionPenalty: sampling.repetitionPenalty,
            repetitionContextSize: sampling.repetitionContextSize,
            prefillStepSize: isGemma4Vision ? 16 : 512
        )
    }

    private static func wiredMemoryTicket(modelID: String, isVision: Bool) -> WiredMemoryTicket? {
        let normalized = modelID.lowercased()
        guard isVision, normalized.contains("gemma-4") || normalized.contains("gemma4") else {
            return nil
        }

        let tier = DeviceTier.current()
        let bytes = Int(tier.jetsamSoftLimitGB * 1024 * 1024 * 1024)
        return WiredFixedPolicy(limit: bytes).ticket(size: bytes, kind: .active)
    }

    private static func generateStreamWithMemoryPolicy(
        input: LMInput,
        parameters: GenerateParameters,
        context: ModelContext,
        modelID: String,
        isVision: Bool
    ) async throws -> AsyncStream<Generation> {
        guard let ticket = wiredMemoryTicket(modelID: modelID, isVision: isVision) else {
            return try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
        }

        Self.auditLog("wiredMemory.start model=\"\(modelID)\" vision=\(isVision) bytes=\(ticket.size)")
        return try await WiredMemoryTicket.withWiredLimit(ticket) {
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context,
                wiredMemoryTicket: ticket
            )
            Self.auditLog("wiredMemory.generatorReady model=\"\(modelID)\" vision=\(isVision)")
            return stream
        }
    }

    private static func visionMaxPixelSize(modelID: String, isVision: Bool) -> Int {
        guard isVision else { return 0 }
        let normalized = modelID.lowercased()
        if normalized.contains("gemma-4") || normalized.contains("gemma4") {
            return 160
        }
        if normalized.contains("lfm2.5-vl") {
            return 256
        }
        if normalized.contains("qwen3-vl-4b") || normalized.contains("qwen3vl-4b") {
            return 224
        }
        if normalized.contains("4b") || normalized.contains("8b") || normalized.contains("9b") {
            return 384
        }
        return 512
    }

    private static func patchVisionProcessorConfigIfNeeded(modelID: String, modelDirectory: URL) throws {
        let normalized = modelID.lowercased()
        guard normalized.contains("gemma-4") || normalized.contains("gemma4") else { return }
        let targetSize = visionMaxPixelSize(modelID: modelID, isVision: true)
        let configURLs = [
            modelDirectory.appending(component: "preprocessor_config.json"),
            modelDirectory.appending(component: "processor_config.json")
        ]
        var patchedExistingConfig = false

        for url in configURLs where FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            var size = json["size"] as? [String: Any] ?? [:]
            let currentHeight = size["height"] as? Int
            let currentWidth = size["width"] as? Int
            guard currentHeight != targetSize || currentWidth != targetSize else { continue }

            size["height"] = targetSize
            size["width"] = targetSize
            json["size"] = size
            let patched = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try patched.write(to: url, options: .atomic)
            mlxLogger.log("Patched Gemma 4 processor image size to \(targetSize)x\(targetSize) at \(url.lastPathComponent, privacy: .public)")
            patchedExistingConfig = true
        }

        if !patchedExistingConfig && !configURLs.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            let generatedURL = modelDirectory.appending(component: "processor_config.json")
            let json: [String: Any] = [
                "processor_class": "Gemma4Processor",
                "do_normalize": true,
                "image_mean": [0.5, 0.5, 0.5],
                "image_std": [0.5, 0.5, 0.5],
                "image_seq_length": 280,
                "image_token_id": 258_880,
                "boi_token_id": 255_999,
                "eoi_token_id": 258_882,
                "size": [
                    "height": targetSize,
                    "width": targetSize
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: generatedURL, options: .atomic)
            mlxLogger.log("Generated Gemma 4 processor config at \(generatedURL.lastPathComponent, privacy: .public) with image size \(targetSize)x\(targetSize)")
        }
    }

    func generateStream(prompt: String, modelID: String, systemPrompt: String, maxTokens: Int = 1024, imageData: Data? = nil, isVision: Bool = false, chatHistory: [Chat.Message] = []) async throws -> AsyncStream<String> {
        // Clear GPU cache before vision to maximize available memory for the vision encoder
        if isVision {
            Memory.clearCache()
        }
        Self.auditLog("ensureModel.start model=\"\(modelID)\" vision=\(isVision)")
        let container = try await ensureModel(modelID, isVision: isVision)
        Self.auditLog("ensureModel.done model=\"\(modelID)\" vision=\(isVision)")

        let sampling = samplingPreset(for: modelID, isVision: isVision)
        let parameters = Self.generateParameters(
            modelID: modelID,
            maxTokens: maxTokens,
            isVision: isVision,
            sampling: sampling
        )
        // Never attach images to non-vision containers.
        let visionMaxPixelSize = Self.visionMaxPixelSize(modelID: modelID, isVision: isVision)
        let images = isVision ? Self.ciImages(from: imageData, maxPixelSize: visionMaxPixelSize) : []
        let userInput: UserInput
        if isOpenELM(modelID) {
            userInput = UserInput(prompt: .text(OpenELMPromptTemplate.render(prompt: prompt)))
        } else if isLFMText(modelID) {
            userInput = UserInput(prompt: .text(LFMPromptTemplate.render(systemPrompt: systemPrompt, prompt: prompt)))
        } else {
            // Build proper multi-turn chat: optional system + history + current user message.
            var chat: [Chat.Message] = []
            if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chat.append(.system(systemPrompt))
            }
            chat.append(contentsOf: chatHistory)
            chat.append(.user(prompt, images: images))
            userInput = UserInput(chat: chat, processing: Self.mediaProcessing(isVision: isVision, maxPixelSize: visionMaxPixelSize))
        }
        Self.auditLog("prepare.start model=\"\(modelID)\" vision=\(isVision) images=\(images.count)")
        let input = try await container.perform { context in
            try await context.processor.prepare(input: userInput)
        }
        Self.auditLog("prepare.done model=\"\(modelID)\" vision=\(isVision)")

        Self.auditLog("stream.start model=\"\(modelID)\" vision=\(isVision) maxTokens=\(maxTokens)")
        let mlxStream: AsyncStream<Generation> = try await container.perform { context in
            try await Self.generateStreamWithMemoryPolicy(
                input: input,
                parameters: parameters,
                context: context,
                modelID: modelID,
                isVision: isVision
            )
        }
        Self.auditLog("stream.ready model=\"\(modelID)\" vision=\(isVision)")
        return AsyncStream<String> { continuation in
            Task {
                var yieldedFirstChunk = false
                for await generation in mlxStream {
                    if let chunk = generation.chunk {
                        if !yieldedFirstChunk {
                            yieldedFirstChunk = true
                            Self.auditLog("stream.firstChunk model=\"\(modelID)\" vision=\(isVision)")
                        }
                        continuation.yield(chunk)
                    }
                }
                Self.auditLog("stream.done model=\"\(modelID)\" vision=\(isVision) yieldedFirstChunk=\(yieldedFirstChunk)")
                if isVision {
                    await MLXRuntime.shared.clearGPUCache()
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

    func unloadAndClearCache() {
        unload()
        Memory.clearCache()
    }

    func clearGPUCache() {
        Memory.clearCache()
    }

    /// Delete the on-disk Hub snapshot cache for a downloaded MLX model.
    /// The cache lives at `<CachesDir>/huggingface/hub/models--<org>--<repo>/`.
    func removeModelCache(for modelID: String) {
        guard let cacheDir = MLXModelCache.cacheDirectory(for: modelID) else { return }
        try? FileManager.default.removeItem(at: cacheDir)
        mlxLogger.log("MLX Hub cache removed for: \(modelID, privacy: .public)")
    }

    /// Pre-download an MLX model with progress reporting.
    /// Downloads files to disk only — does NOT load weights into GPU memory.
    func preloadModel(_ modelID: String, isVision: Bool = false, progress: @escaping @Sendable (MLXDownloadProgress) -> Void) async throws {
        mlxLogger.log("Downloading MLX model (no GPU load): \(modelID, privacy: .public)")
        let downloader = HuggingFaceDownloader(authenticatedHubClient())
        // Use downloadModel() which only downloads files via hub.snapshot() —
        // does NOT load weights into GPU memory, avoiding OOM on 8GB devices.
        _ = try await downloader.download(id: modelID, revision: "main", matching: mlxSnapshotFilePatterns, useLatest: false) { p in
            let fraction = p.fractionCompleted
            mlxLogger.log("MLX download progress: \(fraction), \(p.completedUnitCount) / \(p.totalUnitCount)")
            progress(MLXDownloadProgress(
                fraction: fraction,
                completedUnitCount: p.completedUnitCount,
                totalUnitCount: p.totalUnitCount
            ))
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
        imageData: Data? = nil,
        settings: AppSettings? = nil
    ) async throws -> ChatMessage {
        guard let mlxModelID = model.catalogItem.mlxModelID else {
            throw InferenceServiceError.missingLocalModelFile
        }
        if Self.isUnreliableOpenELM(model) {
            return ChatMessage(
                role: .assistant,
                text: AssistantResponseFallback.unreliableOpenELM,
                citations: []
            )
        }
        let runtimeProfile = RuntimeProfileStore().profile(for: model.catalogItem.id)
            ?? .safeMinimum(catalogID: model.catalogItem.id)
        try Self.validateImageInput(
            imageData: imageData,
            model: model,
            modelID: mlxModelID,
            runtimeProfile: runtimeProfile
        )

        let isVision = await MLXRuntime.shared.shouldUseVisionFactory(
            modelID: mlxModelID,
            supportsVision: Self.allowsImageInput(model: model, runtimeProfile: runtimeProfile),
            imageData: imageData
        )
        let baseMaxTokens = InferenceBudget.maxGeneratedTokens(for: model, searchContext: searchContext)
        let maxGeneratedTokens = tunedMaxTokens(for: model, base: baseMaxTokens, isVision: isVision)
        let boundedPrompt = Self.boundedCurrentPrompt(prompt, model: model, isVision: isVision)
        let fullSystemPrompt = isVision
            ? Self.buildVisionSystemPrompt(systemPrompt: effectiveSystemPrompt(systemPrompt, model: model))
            : Self.buildSystemPrompt(
                systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
                searchContext: searchContext,
                model: model,
                maxGeneratedTokens: maxGeneratedTokens
            )
        let history = Self.buildChatHistory(
            conversation: conversation,
            model: model,
            searchContext: searchContext,
            maxGeneratedTokens: maxGeneratedTokens,
            isVision: isVision
        )

        do {
            let response = try await MLXRuntime.shared.generate(
                prompt: boundedPrompt,
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
        imageData: Data? = nil,
        settings: AppSettings? = nil
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        guard let mlxModelID = model.catalogItem.mlxModelID else {
            throw InferenceServiceError.missingLocalModelFile
        }
        if Self.isUnreliableOpenELM(model) {
            let messageID = UUID()
            let stream = AsyncStream<StreamEvent> { continuation in
                continuation.yield(.textDelta(AssistantResponseFallback.unreliableOpenELM))
                continuation.yield(.done)
                continuation.finish()
            }
            return (messageID: messageID, stream: stream)
        }
        let runtimeProfile = RuntimeProfileStore().profile(for: model.catalogItem.id)
            ?? .safeMinimum(catalogID: model.catalogItem.id)
        try Self.validateImageInput(
            imageData: imageData,
            model: model,
            modelID: mlxModelID,
            runtimeProfile: runtimeProfile
        )

        let isVision = await MLXRuntime.shared.shouldUseVisionFactory(
            modelID: mlxModelID,
            supportsVision: Self.allowsImageInput(model: model, runtimeProfile: runtimeProfile),
            imageData: imageData
        )
        let baseMaxTokens = InferenceBudget.maxGeneratedTokens(for: model, searchContext: searchContext)
        let maxGeneratedTokens = tunedMaxTokens(for: model, base: baseMaxTokens, isVision: isVision)
        let boundedPrompt = Self.boundedCurrentPrompt(prompt, model: model, isVision: isVision)
        let fullSystemPrompt = isVision
            ? Self.buildVisionSystemPrompt(systemPrompt: effectiveSystemPrompt(systemPrompt, model: model))
            : Self.buildSystemPrompt(
                systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
                searchContext: searchContext,
                model: model,
                maxGeneratedTokens: maxGeneratedTokens
            )
        let history = Self.buildChatHistory(
            conversation: conversation,
            model: model,
            searchContext: searchContext,
            maxGeneratedTokens: maxGeneratedTokens,
            isVision: isVision
        )

        let messageID = UUID()
        do {
            let rawStream = try await MLXRuntime.shared.generateStream(
                prompt: boundedPrompt,
                modelID: mlxModelID,
                systemPrompt: fullSystemPrompt,
                maxTokens: maxGeneratedTokens,
                imageData: imageData,
                isVision: isVision,
                chatHistory: history
            )
            let timeout = DeviceTier.current() == .compact ? 30.0 : (settings?.inferenceV2Timeout ?? AppSettings.default.inferenceV2Timeout)
            let activeThinkFormats = Set(runtimeProfile.verifiedThinking.map { [$0] } ?? [])
            let processor = StreamProcessor(
                rawStream: rawStream,
                leakTokens: runtimeProfile.knownLeakTokens,
                v2Enabled: settings?.streamProcessorV2Enabled ?? AppSettings.default.streamProcessorV2Enabled,
                hangTimeout: timeout,
                repetitionNgram: 6,
                repetitionCount: 3,
                activeThinkFormats: activeThinkFormats
            )
            return (messageID: messageID, stream: await processor.process())
        } catch {
            throw InferenceServiceError.runtimeUnavailable(Self.friendlyMLXError(error))
        }
    }

    /// Tool definition injection is handled centrally by ChatView to ensure
    /// consistent behavior across GGUF and MLX runtimes and to avoid wasting
    /// context window space with duplicate definitions.
    private func effectiveSystemPrompt(_ base: String, model: InstalledModel) -> String {
        if model.catalogItem.family == .openELM {
            // OpenELM lane bypasses system-role injection entirely.
            return ""
        }
        return base
    }

    private static func allowsImageInput(model: InstalledModel, runtimeProfile: RuntimeProfile) -> Bool {
        runtimeProfile.verifiedVision == .imageAndText
            || (isSourceVisionAuditRun && model.catalogItem.sourceSupportsVision)
    }

    private static var isSourceVisionAuditRun: Bool {
        let args = CommandLine.arguments
        return args.contains("--localai-run-model-audit") && args.contains("--localai-audit-source-vision")
    }

    private static func validateImageInput(
        imageData: Data?,
        model: InstalledModel,
        modelID: String,
        runtimeProfile: RuntimeProfile
    ) throws {
        if imageData != nil && !Self.allowsImageInput(model: model, runtimeProfile: runtimeProfile) {
            if model.catalogItem.family == .gemma && model.catalogItem.sourceSupportsVision {
                throw InferenceServiceError.runtimeUnavailable(
                    "Gemma 4 image input is disabled in this build because the bundled Swift MLX VLM runtime is memory-killed by iOS during image prefill on this device. Text chat stays available; use Qwen 3.5 VL or LFM2.5 VL for image prompts until the Gemma 4 unified/mobile runtime is integrated."
                )
            }
            throw InferenceServiceError.runtimeUnavailable(
                "Image input is not verified for this model in the app runtime. Run diagnostics or choose a green-audited MLX vision model."
            )
        }
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
            return "This model architecture is not supported by the bundled MLX runtime. Use a supported catalog model such as Qwen 3.5 VL or LFM2.5 VL for image prompts."
        }
        if desc.contains("TokenizersBackend") {
            return "This LFM model needs the tokenizer compatibility patch. Install the latest build and try the model again."
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
        if model.catalogItem.family == .openELM {
            return ""
        }
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

    private static func buildVisionSystemPrompt(systemPrompt: String) -> String {
        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "You are running locally on-device. Answer the user's image question directly and concisely."
        }
        return "\(trimmed)\nAnswer the user's image question directly and concisely. Keep the response short enough for on-device memory."
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
        maxGeneratedTokens: Int,
        isVision: Bool = false
    ) -> [Chat.Message] {
        // VLM image turns need the smallest possible prefill on iPhone. The
        // image encoder and prompt prefill peak together, so prior text history
        // is intentionally dropped for image turns.
        if isVision {
            return []
        }
        // OpenELM is very small-context; keeping long history causes topic drift/noise.
        if model.catalogItem.family == .openELM {
            return []
        }
        let historyBudget = InferenceBudget.mlxHistoryBudget(
            for: model,
            searchContext: searchContext,
            maxGeneratedTokens: maxGeneratedTokens
        )
        var turns: [Chat.Message] = []
        var usedTokens = 0
        var retainedMessages = 0
        let maxMessages = InferenceBudget.maxHistoryMessages(
            for: model,
            searchContext: searchContext
        )
        let maxCharacters = InferenceBudget.maxHistoryCharactersPerMessage(for: model)

        for message in conversation.reversed() {
            if AssistantResponseFallback.shouldSkipInHistory(message) {
                continue
            }
            switch message.role {
            case .user, .assistant: break
            default: continue  // skip system notices
            }
            let text = InferenceBudget.trimHistoryText(message.text, maxCharacters: maxCharacters)
            let cost = max(1, text.utf8.count / 4)
            if usedTokens + cost > historyBudget { break }
            switch message.role {
            case .assistant: turns.insert(.assistant(text), at: 0)
            case .user:      turns.insert(.user(text), at: 0)
            default:         break
            }
            usedTokens += cost
            retainedMessages += 1
            if retainedMessages >= maxMessages { break }
        }
        return turns
    }

    private static func boundedCurrentPrompt(_ prompt: String, model: InstalledModel, isVision: Bool = false) -> String {
        let maxCharacters = isVision ? 1_200 : InferenceBudget.maxHistoryCharactersPerMessage(for: model) * 2
        return InferenceBudget.trimHistoryText(prompt, maxCharacters: maxCharacters)
    }

    private func tunedMaxTokens(for model: InstalledModel, base: Int, isVision: Bool) -> Int {
        if isVision {
            if model.catalogItem.family == .gemma || model.catalogItem.parameterSize.contains("4") {
                return min(base, 96)
            }
            return min(base, 128)
        }
        if model.catalogItem.family == .openELM {
            return min(base, 64)
        }
        if model.catalogItem.family == .lfm && model.catalogItem.parameterSize == "350M" {
            return min(base, 512)
        }
        return base
    }

    private static func isUnreliableOpenELM(_ model: InstalledModel) -> Bool {
        model.catalogItem.family == .openELM
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
        imageData: Data? = nil,
        settings: AppSettings? = nil
    ) async throws -> ChatMessage {
        throw MLXInferenceError.runtimeUnavailable
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
        throw MLXInferenceError.runtimeUnavailable
    }
}

#endif
