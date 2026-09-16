import Foundation
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelService {
    static let localPathMarker = "system://apple-intelligence/foundation-models/default"

    static let textOnlyMessage = "Apple's Foundation Models app API is text-only here. Use Qwen 3.5 VL or LFM2.5 VL for image understanding."
    static let visionUnavailableMessage = "Image input needs iOS 27 or later with Apple Intelligence. Use Qwen 3.5 VL or LFM2.5 VL for image understanding on this device."

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

    /// Whether the on-device system model accepts images.
    ///
    /// The WWDC26 system model advertises `.vision` (iOS 27+). On iOS 26 the
    /// Foundation Models app API is text-only, which is why image input used to
    /// be refused outright. This is a runtime capability check, not a version
    /// guess: the OS reports whether the feature is actually usable.
    static var supportsVision: Bool {
#if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            return SystemLanguageModel.default.capabilities.contains(.vision)
        }
#endif
        return false
    }

    /// Whether the system model advertises tool calling (iOS 27+).
    static var supportsToolCalling: Bool {
#if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            return SystemLanguageModel.default.capabilities.contains(.toolCalling)
        }
#endif
        return false
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
        try Self.validateImageSupport(imageData)

        let text = try await generateText(
            prompt: prompt,
            conversation: conversation,
            searchContext: searchContext,
            systemPrompt: systemPrompt,
            imageData: imageData
        )
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
        try Self.validateImageSupport(imageData)

        let messageID = UUID()
        let stream = AsyncStream<StreamEvent> { continuation in
            Task {
                let streamStart = Date()
                do {
                    let text = try await generateText(
                        prompt: prompt,
                        conversation: conversation,
                        searchContext: searchContext,
                        systemPrompt: systemPrompt,
                        imageData: imageData
                    )
                    let firstTokenTime = Date().timeIntervalSince(streamStart)
                    continuation.yield(.textDelta(text))
                    continuation.yield(.done(GenerationStats(
                        timeToFirstToken: firstTokenTime,
                        totalDuration: Date().timeIntervalSince(streamStart),
                        deltaCount: 1
                    )))
                } catch {
                    continuation.yield(.textDelta(error.localizedDescription))
                    continuation.yield(.done(GenerationStats(totalDuration: Date().timeIntervalSince(streamStart))))
                }
                continuation.finish()
            }
        }
        return (messageID, stream)
    }

    /// Images are accepted only where the system model actually supports them.
    static func validateImageSupport(_ imageData: Data?) throws {
        guard imageData != nil else { return }
        guard AppleFoundationModelService.supportsVision else {
            throw InferenceServiceError.runtimeUnavailable(AppleFoundationModelService.visionUnavailableMessage)
        }
    }

    private func generateText(
        prompt: String,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> String {
        if let message = AppleFoundationModelService.availabilityMessage {
            throw InferenceServiceError.runtimeUnavailable(message)
        }

#if canImport(FoundationModels)
        // iOS 27+: the system model can take the image directly in the prompt.
        if #available(iOS 27.0, *), let imageData {
            let session = LanguageModelSession(
                instructions: buildInstructions(systemPrompt: systemPrompt, searchContext: searchContext)
            )
            let response = try await session.respond(
                to: try Self.visionPrompt(
                    text: buildPromptText(prompt: prompt, conversation: conversation),
                    imageData: imageData
                ),
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 512)
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: buildInstructions(systemPrompt: systemPrompt, searchContext: searchContext))
            let response = try await session.respond(
                to: buildPromptText(prompt: prompt, conversation: conversation),
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 512)
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
#endif

        throw InferenceServiceError.runtimeUnavailable("Apple Intelligence Foundation Models require iOS 26 or later.")
    }

#if canImport(FoundationModels)
    /// Builds a multimodal prompt: the text turn plus the attached image.
    ///
    /// `Attachment` conforms to `PromptRepresentable`, so it composes inside the
    /// `@PromptBuilder` closure alongside the text. (`Transcript.Prompt` is the
    /// transcript-side type and is not what `respond(to:)` accepts.)
    @available(iOS 27.0, *)
    static func visionPrompt(text: String, imageData: Data) throws -> Prompt {
        guard let cgImage = UIImage(data: imageData)?.cgImage else {
            throw InferenceServiceError.runtimeUnavailable("The attached image could not be decoded.")
        }

        let image = Attachment<ImageAttachmentContent>(cgImage).label("Attached image")
        return Prompt {
            text
            image
        }
    }
#endif

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

    private func buildPromptText(prompt: String, conversation: [ChatMessage]) -> String {
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
