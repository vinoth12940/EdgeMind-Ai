import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelService {
    static let localPathMarker = "system://apple-intelligence/foundation-models/default"

    static var availabilityMessage: String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "Apple Intelligence is not available on this device."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is installed by the system, but it is not turned on. Enable it in Settings to use this model."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading or preparing its system model. Try again after iOS finishes setup."
            @unknown default:
                return "Apple Intelligence is not available right now."
            }
        }
#endif
        return "Apple Intelligence Foundation Models require iOS 26 or later."
    }
}

struct AppleFoundationInferenceService: InferenceService {
    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil,
        settings: AppSettings? = nil
    ) async throws -> ChatMessage {
        guard imageData == nil else {
            throw InferenceServiceError.runtimeUnavailable("Apple's Foundation Models app API is text-only here. Use Qwen 3.5 VL or LFM2.5 VL for image understanding.")
        }

        let text = try await generateText(prompt: prompt, conversation: conversation, searchContext: searchContext, systemPrompt: systemPrompt)
        return ChatMessage(role: .assistant, text: text, citations: searchContext?.citations ?? [])
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
        guard imageData == nil else {
            throw InferenceServiceError.runtimeUnavailable("Apple's Foundation Models app API is text-only here. Use Qwen 3.5 VL or LFM2.5 VL for image understanding.")
        }

        let messageID = UUID()
        let stream = AsyncStream<StreamEvent> { continuation in
            Task {
                do {
                    let text = try await generateText(prompt: prompt, conversation: conversation, searchContext: searchContext, systemPrompt: systemPrompt)
                    continuation.yield(.textDelta(text))
                    continuation.yield(.done)
                } catch {
                    continuation.yield(.textDelta(error.localizedDescription))
                    continuation.yield(.done)
                }
                continuation.finish()
            }
        }
        return (messageID, stream)
    }

    private func generateText(
        prompt: String,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String
    ) async throws -> String {
        if let message = AppleFoundationModelService.availabilityMessage {
            throw InferenceServiceError.runtimeUnavailable(message)
        }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: buildInstructions(systemPrompt: systemPrompt, searchContext: searchContext))
            let response = try await session.respond(
                to: buildPrompt(prompt: prompt, conversation: conversation),
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 512)
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
#endif

        throw InferenceServiceError.runtimeUnavailable("Apple Intelligence Foundation Models require iOS 26 or later.")
    }

    private func buildInstructions(systemPrompt: String, searchContext: SearchContext?) -> String {
        var parts = [
            systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            "Answer directly and concisely. Do not claim to be a downloaded MLX or GGUF model."
        ].filter { !$0.isEmpty }

        if let searchContext {
            var sourceLines = searchContext.snippets.map { "- \($0.prefix(350))" }
            if let answer = searchContext.answer, !answer.isEmpty {
                sourceLines.insert("- \(answer.prefix(350))", at: 0)
            }
            parts.append("Use these search results when relevant:\n\(sourceLines.joined(separator: "\n"))")
        }

        return parts.joined(separator: "\n\n")
    }

    private func buildPrompt(prompt: String, conversation: [ChatMessage]) -> String {
        let recentTurns = conversation
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(6)
            .map { "\($0.role.rawValue.capitalized): \($0.text)" }
            .joined(separator: "\n")

        if recentTurns.isEmpty {
            return prompt
        }

        return """
        Recent conversation:
        \(recentTurns)

        User: \(prompt)
        Assistant:
        """
    }
}
