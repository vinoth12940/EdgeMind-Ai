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

struct LocalLlamaChatTurn: Sendable {
    let role: String
    let content: String
}

struct LocalLlamaPreparedPrompt {
    let text: String
    let addBOS: Bool
    let parseSpecial: Bool
}

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

    static func create(modelPath: String, maxGeneratedTokens: Int32 = 1024, nCtx: Int32 = 4096) throws -> LocalLlamaContext {
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
        contextParams.n_ctx = UInt32(nCtx)
        contextParams.n_batch = 512
        contextParams.n_ubatch = 512
        contextParams.n_threads = Int32(nThreads)
        contextParams.n_threads_batch = Int32(nThreads)
        contextParams.flash_attn_type = DeviceCapabilityService.supportsFlashAttention()
            ? LLAMA_FLASH_ATTN_TYPE_ENABLED
            : LLAMA_FLASH_ATTN_TYPE_DISABLED
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

        // Sampling presets:
        // - Gemma 4: temp=1.0, top_k=64, top_p=0.95, rep_penalty=1.0
        //   (https://unsloth.ai/docs/models/gemma-4)
        // - Qwen (llama.cpp guide): temp=0.6, top_k=20, top_p=0.95
        //   and add a light presence penalty to reduce repetition loops.
        //   (https://qwen.readthedocs.io/en/latest/run_locally/llama.cpp.html)
        let isGemma4 = normalizedPath.lowercased().contains("gemma-4") || normalizedPath.lowercased().contains("gemma4")
        let isQwen = normalizedPath.lowercased().contains("qwen")
        let topK: Int32 = isGemma4 ? 64 : (isQwen ? 20 : 40)
        let topP: Float = isGemma4 ? 0.95 : (isQwen ? 0.95 : 0.9)
        let temp: Float = isGemma4 ? 1.0 : (isQwen ? 0.6 : 0.7)
        let repPenalty: Float = isGemma4 ? 1.0 : (isQwen ? 1.05 : 1.1)
        let presencePenalty: Float = isQwen ? 0.2 : 0.0

        llama_sampler_chain_add(sampling, llama_sampler_init_top_k(topK))
        llama_sampler_chain_add(sampling, llama_sampler_init_top_p(topP, 1))
        llama_sampler_chain_add(sampling, llama_sampler_init_min_p(0.05, 1))
        llama_sampler_chain_add(sampling, llama_sampler_init_temp(temp))
        llama_sampler_chain_add(sampling, llama_sampler_init_penalties(64, repPenalty, 0.0, presencePenalty))
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

    func generate(prompt: String, addBOS: Bool = true, parseSpecial: Bool = false) throws -> String {
        clear()
        promptTokens = tokenize(text: prompt, addBOS: addBOS, parseSpecial: parseSpecial)
        guard !promptTokens.isEmpty else {
            throw LocalLlamaRuntimeError.tokenizationFailed
        }

        // If prompt is too large, truncate from the middle (keep system prefix + recent suffix)
        let maxPromptTokens = max(256, Int(contextSize - maxGeneratedTokens - 64))
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

    func generateStream(prompt: String, addBOS: Bool = true, parseSpecial: Bool = false) throws -> AsyncStream<String> {
        clear()
        runtimeLogger.log("generateStream: addBOS=\(addBOS) parseSpecial=\(parseSpecial) promptLen=\(prompt.count)")
        runtimeLogger.log("Prompt first 300 chars: \(String(prompt.prefix(300)), privacy: .public)")
        promptTokens = tokenize(text: prompt, addBOS: addBOS, parseSpecial: parseSpecial)
        guard !promptTokens.isEmpty else {
            throw LocalLlamaRuntimeError.tokenizationFailed
        }
        if promptTokens.count >= 3 {
            runtimeLogger.log("First 3 token IDs: \(self.promptTokens[0]), \(self.promptTokens[1]), \(self.promptTokens[2])")
        }

        let maxPromptTokens = max(256, Int(contextSize - maxGeneratedTokens - 64))
        if promptTokens.count > maxPromptTokens {
            let keepFront = maxPromptTokens / 4
            let keepBack  = maxPromptTokens - keepFront
            runtimeLogger.warning("Stream prompt too large (\(self.promptTokens.count) tokens). Truncating to \(maxPromptTokens) (front=\(keepFront) back=\(keepBack))")
            promptTokens = Array(promptTokens.prefix(keepFront)) + Array(promptTokens.suffix(keepBack))
        }

        runtimeLogger.log("Streaming generation with prompt tokens=\(self.promptTokens.count) maxGenerated=\(self.maxGeneratedTokens) ctx=\(self.contextSize)")
        try prefillPrompt()

        return AsyncStream { continuation in
            let producer = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                while await !self.isDone {
                    if Task.isCancelled {
                        await self.cancelGeneration()
                        break
                    }
                    do {
                        let piece = try await self.generationStep()
                        if !piece.isEmpty {
                            continuation.yield(piece)
                        }
                    } catch is CancellationError {
                        await self.cancelGeneration()
                        break
                    } catch {
                        runtimeLogger.error("Stream generation error: \(error.localizedDescription)")
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                producer.cancel()
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
        if Task.isCancelled {
            isDone = true
            throw CancellationError()
        }

        let token = llama_sampler_sample(sampling, context, -1)
        llama_sampler_accept(sampling, token)

        if llama_vocab_is_eog(vocab, token) || generatedTokenCount >= maxGeneratedTokens {
            if generatedTokenCount == 0 {
                runtimeLogger.error("⚠️ IMMEDIATE EOG: First sampled token is EOG (token=\(token)). Model produced zero output. Prompt may be malformed (double BOS?).")
            } else {
                runtimeLogger.log("Generation complete: \(self.generatedTokenCount) tokens produced (eog=\(llama_vocab_is_eog(self.vocab, token)))")
            }
            isDone = true
            defer { partialUTF8Buffer.removeAll() }
            return String(validatingUTF8: partialUTF8Buffer + [0]) ?? ""
        }

        generatedTokenCount += 1

        if generatedTokenCount <= 5 {
            runtimeLogger.log("Token[\(self.generatedTokenCount)]: id=\(token)")
        }

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

    private func cancelGeneration() {
        isDone = true
        partialUTF8Buffer.removeAll()
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

    private func tokenize(text: String, addBOS: Bool, parseSpecial: Bool = false) -> [llama_token] {
        let utf8Count = text.utf8.count
        let capacity = utf8Count + (addBOS ? 1 : 0) + 1
        let tokenBuffer = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { tokenBuffer.deallocate() }

        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokenBuffer, Int32(capacity), addBOS, parseSpecial)
        guard tokenCount > 0 else { return [] }
        return (0 ..< Int(tokenCount)).map { tokenBuffer[$0] }
    }

    private func tokenToPiece(_ token: llama_token) -> [CChar] {
        var result = [CChar](repeating: 0, count: 256)
        var count = llama_token_to_piece(vocab, token, &result, Int32(result.count), 0, true)

        if count < 0 {
            result = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &result, Int32(result.count), 0, true)
        }

        guard count > 0 else { return [] }
        return Array(result.prefix(Int(count)))
    }

    func preparePrompt(chat: [LocalLlamaChatTurn], fallback fallbackPrompt: String) -> LocalLlamaPreparedPrompt {
        guard let templatedPrompt = applyChatTemplate(chat: chat), !templatedPrompt.isEmpty else {
            runtimeLogger.log("Using fallback raw-text prompt (no chat template in model)")
            let shouldParseSpecial = fallbackPrompt.contains("<start_of_turn>") || fallbackPrompt.contains("<end_of_turn>") || fallbackPrompt.contains("<|turn>") || fallbackPrompt.contains("<turn|>")
            return LocalLlamaPreparedPrompt(text: fallbackPrompt, addBOS: true, parseSpecial: shouldParseSpecial)
        }

        runtimeLogger.log("Chat template applied successfully (\(templatedPrompt.count) chars)")
        runtimeLogger.log("Template preview: \(String(templatedPrompt.prefix(300)), privacy: .public)")
        // addBOS must be FALSE when parseSpecial is TRUE and the template output already
        // includes <bos> (Gemma 4, Qwen 3, etc.). Setting both to true causes double-BOS
        // which makes the model produce immediate EOG (empty output).
        // This matches the official llama.cpp simple-chat pattern:
        //   tokenize(prompt, add_special=false, parse_special=true)
        let templateStartsWithBos = templatedPrompt.hasPrefix("<bos>") || templatedPrompt.hasPrefix("<s>")
        runtimeLogger.log("Template starts with BOS: \(templateStartsWithBos) → addBOS: \(!templateStartsWithBos)")
        return LocalLlamaPreparedPrompt(text: templatedPrompt, addBOS: !templateStartsWithBos, parseSpecial: true)
    }

    private func applyChatTemplate(chat: [LocalLlamaChatTurn]) -> String? {
        guard !chat.isEmpty, let templatePointer = llama_model_chat_template(model, nil) else {
            return nil
        }

        let rolePointers = chat.map { strdup($0.role) }
        let contentPointers = chat.map { strdup($0.content) }
        defer {
            rolePointers.forEach { free($0) }
            contentPointers.forEach { free($0) }
        }

        var messages = zip(rolePointers, contentPointers).map { rolePointer, contentPointer in
            llama_chat_message(role: UnsafePointer(rolePointer), content: UnsafePointer(contentPointer))
        }

        let requiredLength = llama_chat_apply_template(templatePointer, &messages, messages.count, true, nil, 0)
        guard requiredLength > 0 else {
            runtimeLogger.warning("llama_chat_apply_template could not format chat; falling back to legacy prompt rendering")
            return nil
        }

        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(requiredLength) + 1)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0, count: Int(requiredLength) + 1)

        let actualLength = llama_chat_apply_template(templatePointer, &messages, messages.count, true, buffer, requiredLength + 1)
        guard actualLength > 0 else {
            runtimeLogger.warning("llama_chat_apply_template failed on second pass; falling back to legacy prompt rendering")
            return nil
        }

        return String(cString: buffer)
    }
}

actor LocalLlamaRuntime {
    static let shared = LocalLlamaRuntime()

    private var activeModelPath: String?
    private var activeMaxGeneratedTokens: Int32?
    private var activeContext: LocalLlamaContext?
    private var isLoading = false

    /// Ensures a context is loaded for the given model path and token limits.
    /// Reloads if the model path or maxGeneratedTokens changes.
    /// Guards against concurrent loads with `isLoading`.
    private func ensureContext(for modelPath: String, maxGeneratedTokens: Int32) throws -> LocalLlamaContext {
        guard !isLoading else { throw LocalLlamaRuntimeError.couldNotInitializeContext }
        let needsReload = activeModelPath != modelPath
            || activeContext == nil
            || activeMaxGeneratedTokens != maxGeneratedTokens
        if needsReload {
            isLoading = true
            defer { isLoading = false }
            activeContext = nil  // release before alloc to avoid peak RAM spike
            let nCtx = DeviceCapabilityService.contextSize()
            activeContext = try LocalLlamaContext.create(
                modelPath: modelPath,
                maxGeneratedTokens: maxGeneratedTokens,
                nCtx: nCtx
            )
            activeModelPath = modelPath
            activeMaxGeneratedTokens = maxGeneratedTokens
        }
        guard let ctx = activeContext else { throw LocalLlamaRuntimeError.couldNotInitializeContext }
        return ctx
    }

    func generate(prompt: String, using modelPath: String, maxGeneratedTokens: Int32 = 1024) async throws -> String {
        let ctx = try ensureContext(for: modelPath, maxGeneratedTokens: maxGeneratedTokens)
        return try await ctx.generate(prompt: prompt)
    }

    func generate(chat: [LocalLlamaChatTurn], fallbackPrompt: String, using modelPath: String, maxGeneratedTokens: Int32 = 1024) async throws -> String {
        let ctx = try ensureContext(for: modelPath, maxGeneratedTokens: maxGeneratedTokens)
        let preparedPrompt = await ctx.preparePrompt(chat: chat, fallback: fallbackPrompt)
        return try await ctx.generate(prompt: preparedPrompt.text, addBOS: preparedPrompt.addBOS, parseSpecial: preparedPrompt.parseSpecial)
    }

    func generateStream(prompt: String, using modelPath: String, maxGeneratedTokens: Int32 = 1024) async throws -> AsyncStream<String> {
        let ctx = try ensureContext(for: modelPath, maxGeneratedTokens: maxGeneratedTokens)
        return try await ctx.generateStream(prompt: prompt)
    }

    func generateStream(chat: [LocalLlamaChatTurn], fallbackPrompt: String, using modelPath: String, maxGeneratedTokens: Int32 = 1024) async throws -> AsyncStream<String> {
        let ctx = try ensureContext(for: modelPath, maxGeneratedTokens: maxGeneratedTokens)
        let preparedPrompt = await ctx.preparePrompt(chat: chat, fallback: fallbackPrompt)
        return try await ctx.generateStream(prompt: preparedPrompt.text, addBOS: preparedPrompt.addBOS, parseSpecial: preparedPrompt.parseSpecial)
    }

    func unload() {
        activeContext = nil
        activeModelPath = nil
        activeMaxGeneratedTokens = nil
    }
}
