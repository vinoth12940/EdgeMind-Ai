import Foundation
import OSLog
import llama

enum LocalLlamaRuntimeError: LocalizedError {
    case modelFileMissing(String)
    case couldNotInitializeContext
    case couldNotLoadModel(String)
    case tokenizationFailed
    case promptTooLong(tokenCount: Int, contextSize: Int32)
    case decodeFailed(stage: String)

    var errorDescription: String? {
        switch self {
        case .modelFileMissing(let path):
            return "The downloaded model file is missing at \(path)."
        case .couldNotInitializeContext:
            return "The local runtime could not initialize a generation context."
        case .couldNotLoadModel(let path):
            return "The runtime could not load the model at \(path)."
        case .tokenizationFailed:
            return "The runtime could not tokenize the current prompt."
        case .promptTooLong(let tokenCount, let contextSize):
            return "The prompt is too large for the current context window (\(tokenCount) tokens for a \(contextSize)-token context). Try a shorter chat history or prompt."
        case .decodeFailed(let stage):
            return "The local runtime failed during \(stage)."
        }
    }
}

private let runtimeLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "LocalLlamaRuntime")

private func normalizedModelPath(from rawPath: String) -> String {
    if rawPath.hasPrefix("file://"), let fileURL = URL(string: rawPath), fileURL.isFileURL {
        return fileURL.path(percentEncoded: false)
    }

    if rawPath.contains("%") {
        return rawPath.removingPercentEncoding ?? rawPath
    }

    return rawPath
}

private func llamaBatchClear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llamaBatchAdd(
    _ batch: inout llama_batch,
    token: llama_token,
    position: llama_pos,
    sequenceIDs: [llama_seq_id],
    logits: Bool
) {
    batch.token[Int(batch.n_tokens)] = token
    batch.pos[Int(batch.n_tokens)] = position
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(sequenceIDs.count)
    for index in 0 ..< sequenceIDs.count {
        batch.seq_id[Int(batch.n_tokens)]![index] = sequenceIDs[index]
    }
    batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
}

actor LocalLlamaContext {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private let batchCapacity: Int32
    private let contextSize: Int32
    private var promptTokens: [llama_token] = []
    private var partialUTF8Buffer: [CChar] = []
    private var isDone = false
    private var currentTokenCount: Int32 = 0
    private var generatedTokenCount: Int32 = 0
    private let maxGeneratedTokens: Int32

    private init(
        model: OpaquePointer,
        context: OpaquePointer,
        vocab: OpaquePointer,
        sampling: UnsafeMutablePointer<llama_sampler>,
        maxGeneratedTokens: Int32,
        batchCapacity: Int32,
        contextSize: Int32
    ) {
        self.model = model
        self.context = context
        self.vocab = vocab
        self.sampling = sampling
        self.batchCapacity = batchCapacity
        self.contextSize = contextSize
        self.batch = llama_batch_init(batchCapacity, 0, 1)
        self.maxGeneratedTokens = maxGeneratedTokens
    }

    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_model_free(model)
        llama_free(context)
        llama_backend_free()
    }

    static func create(modelPath: String, maxGeneratedTokens: Int32 = 1024) throws -> LocalLlamaContext {
        let normalizedPath = normalizedModelPath(from: modelPath)
        guard FileManager.default.fileExists(atPath: normalizedPath) else {
            runtimeLogger.error("Model file missing. raw=\(modelPath, privacy: .public) normalized=\(normalizedPath, privacy: .public)")
            throw LocalLlamaRuntimeError.modelFileMissing(normalizedPath)
        }

        llama_backend_init()

        var modelParams = llama_model_default_params()
        modelParams.use_mmap = true

#if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
#endif

        guard let model = llama_model_load_from_file(normalizedPath, modelParams) else {
            runtimeLogger.error("Failed to load model from normalized path \(normalizedPath, privacy: .public)")
            throw LocalLlamaRuntimeError.couldNotLoadModel(normalizedPath)
        }

        guard let vocab = llama_model_get_vocab(model) else {
            llama_model_free(model)
            throw LocalLlamaRuntimeError.couldNotInitializeContext
        }

        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 8192
        contextParams.n_batch = 512
        contextParams.n_ubatch = 512
        contextParams.n_threads = Int32(nThreads)
        contextParams.n_threads_batch = Int32(nThreads)
        contextParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED
        contextParams.offload_kqv = false
        contextParams.op_offload = false
        contextParams.no_perf = true

        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LocalLlamaRuntimeError.couldNotInitializeContext
        }

        let sampling = llama_sampler_chain_init(llama_sampler_chain_default_params())
        guard let sampling else {
            llama_free(context)
            llama_model_free(model)
            throw LocalLlamaRuntimeError.couldNotInitializeContext
        }

        llama_sampler_chain_add(sampling, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampling, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampling, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(sampling, llama_sampler_init_dist(1234))

        let actualBatchCapacity = Int32(llama_n_batch(context))
        let actualContextSize = Int32(llama_n_ctx(context))
        runtimeLogger.log("Initialized llama context for \(normalizedPath, privacy: .public) with n_ctx=\(actualContextSize) n_batch=\(actualBatchCapacity) threads=\(nThreads)")

        return LocalLlamaContext(
            model: model,
            context: context,
            vocab: vocab,
            sampling: sampling,
            maxGeneratedTokens: maxGeneratedTokens,
            batchCapacity: actualBatchCapacity,
            contextSize: actualContextSize
        )
    }

    func generate(prompt: String) throws -> String {
        clear()
        promptTokens = tokenize(text: prompt, addBOS: true)
        guard !promptTokens.isEmpty else {
            throw LocalLlamaRuntimeError.tokenizationFailed
        }

        // If prompt is too large, truncate from the middle (keep system prefix + recent suffix)
        let maxPromptTokens = Int(contextSize - maxGeneratedTokens - 64)
        if promptTokens.count > maxPromptTokens {
            let keepFront = maxPromptTokens / 4          // ~system prompt
            let keepBack  = maxPromptTokens - keepFront  // ~recent conversation + user query
            runtimeLogger.warning("Prompt too large (\(self.promptTokens.count) tokens). Truncating to \(maxPromptTokens) (front=\(keepFront) back=\(keepBack))")
            promptTokens = Array(promptTokens.prefix(keepFront)) + Array(promptTokens.suffix(keepBack))
        }

        runtimeLogger.log("Starting generation with prompt tokens=\(self.promptTokens.count) maxGenerated=\(self.maxGeneratedTokens) ctx=\(self.contextSize)")
        try prefillPrompt()

        var output = ""
        while !isDone {
            output += try generationStep()
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateStream(prompt: String) throws -> AsyncStream<String> {
        clear()
        promptTokens = tokenize(text: prompt, addBOS: true)
        guard !promptTokens.isEmpty else {
            throw LocalLlamaRuntimeError.tokenizationFailed
        }

        let maxPromptTokens = Int(contextSize - maxGeneratedTokens - 64)
        if promptTokens.count > maxPromptTokens {
            let keepFront = maxPromptTokens / 4
            let keepBack  = maxPromptTokens - keepFront
            promptTokens = Array(promptTokens.prefix(keepFront)) + Array(promptTokens.suffix(keepBack))
        }

        runtimeLogger.log("Streaming generation with prompt tokens=\(self.promptTokens.count) ctx=\(self.contextSize)")
        try prefillPrompt()

        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                while await !self.isDone {
                    do {
                        let piece = try await self.generationStep()
                        if !piece.isEmpty {
                            continuation.yield(piece)
                        }
                    } catch {
                        runtimeLogger.error("Stream generation error: \(error.localizedDescription)")
                        break
                    }
                }
                continuation.finish()
            }
        }
    }

    private func prefillPrompt() throws {
        var cursor = 0

        while cursor < promptTokens.count {
            llamaBatchClear(&batch)

            let chunkSize = min(Int(batchCapacity), promptTokens.count - cursor)
            for offset in 0 ..< chunkSize {
                let tokenIndex = cursor + offset
                let isLastPromptToken = tokenIndex == promptTokens.count - 1
                llamaBatchAdd(
                    &batch,
                    token: promptTokens[tokenIndex],
                    position: Int32(tokenIndex),
                    sequenceIDs: [0],
                    logits: isLastPromptToken
                )
            }

            if llama_decode(context, batch) != 0 {
                runtimeLogger.error("Prompt prefill failed at cursor \(cursor) with chunk size \(chunkSize)")
                throw LocalLlamaRuntimeError.decodeFailed(stage: "prompt prefill")
            }

            currentTokenCount = Int32(cursor + chunkSize)
            cursor += chunkSize
        }
    }

    private func generationStep() throws -> String {
        let token = llama_sampler_sample(sampling, context, batch.n_tokens - 1)
        llama_sampler_accept(sampling, token)

        if llama_vocab_is_eog(vocab, token) || generatedTokenCount >= maxGeneratedTokens {
            isDone = true
            defer { partialUTF8Buffer.removeAll() }
            return String(validatingUTF8: partialUTF8Buffer + [0]) ?? ""
        }

        generatedTokenCount += 1

        partialUTF8Buffer.append(contentsOf: tokenToPiece(token))
        let piece = String(validatingUTF8: partialUTF8Buffer + [0]) ?? ""
        if !piece.isEmpty {
            partialUTF8Buffer.removeAll()
        }

        llamaBatchClear(&batch)
        llamaBatchAdd(&batch, token: token, position: currentTokenCount, sequenceIDs: [0], logits: true)
        currentTokenCount += 1

        if llama_decode(context, batch) != 0 {
            runtimeLogger.error("Token decode failed at generated token count \(self.currentTokenCount)")
            throw LocalLlamaRuntimeError.decodeFailed(stage: "token generation")
        }

        return piece
    }

    func clear() {
        promptTokens.removeAll()
        partialUTF8Buffer.removeAll()
        currentTokenCount = 0
        generatedTokenCount = 0
        isDone = false
        llama_sampler_reset(sampling)
        llama_memory_clear(llama_get_memory(context), true)
    }

    private func tokenize(text: String, addBOS: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let capacity = utf8Count + (addBOS ? 1 : 0) + 1
        let tokenBuffer = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { tokenBuffer.deallocate() }

        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokenBuffer, Int32(capacity), addBOS, false)
        guard tokenCount > 0 else { return [] }
        return (0 ..< Int(tokenCount)).map { tokenBuffer[$0] }
    }

    private func tokenToPiece(_ token: llama_token) -> [CChar] {
        var result = [CChar](repeating: 0, count: 8)
        var count = llama_token_to_piece(vocab, token, &result, Int32(result.count), 0, false)

        if count < 0 {
            result = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &result, Int32(result.count), 0, false)
        }

        guard count > 0 else { return [] }
        return Array(result.prefix(Int(count)))
    }
}

actor LocalLlamaRuntime {
    static let shared = LocalLlamaRuntime()

    private var activeModelPath: String?
    private var activeContext: LocalLlamaContext?

    func generate(prompt: String, using modelPath: String) async throws -> String {
        if activeModelPath != modelPath || activeContext == nil {
            activeContext = try LocalLlamaContext.create(modelPath: modelPath)
            activeModelPath = modelPath
        }

        guard let activeContext else {
            throw LocalLlamaRuntimeError.couldNotInitializeContext
        }

        return try await activeContext.generate(prompt: prompt)
    }

    func generateStream(prompt: String, using modelPath: String) async throws -> AsyncStream<String> {
        if activeModelPath != modelPath || activeContext == nil {
            activeContext = try LocalLlamaContext.create(modelPath: modelPath)
            activeModelPath = modelPath
        }

        guard let activeContext else {
            throw LocalLlamaRuntimeError.couldNotInitializeContext
        }

        return try await activeContext.generateStream(prompt: prompt)
    }
}