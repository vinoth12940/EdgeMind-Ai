import Foundation
@testable import EdgeMindAi

/// Returns one scripted event list per `generateStream` call, in order.
/// A script of `nil` produces a stream that emits `firstChunk` and then stays
/// open until the consuming task is cancelled (simulates a long generation).
final class ScriptedInferenceService: InferenceService, @unchecked Sendable {
    struct Call {
        let prompt: String
        let model: InstalledModel
        let systemPrompt: String
        let conversation: [ChatMessage]
        let imageData: Data?
    }

    private var scripts: [[StreamEvent]?]
    private(set) var calls: [Call] = []
    let firstChunk: String

    init(scripts: [[StreamEvent]?], firstChunk: String = "partial") {
        self.scripts = scripts
        self.firstChunk = firstChunk
    }

    func generateReply(
        prompt: String, model: InstalledModel, conversation: [ChatMessage],
        searchContext: SearchContext?, systemPrompt: String, imageData: Data?, settings: AppSettings?
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, text: "unused")
    }

    func generateStream(
        prompt: String, model: InstalledModel, conversation: [ChatMessage],
        searchContext: SearchContext?, systemPrompt: String, imageData: Data?, settings: AppSettings?
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        calls.append(Call(prompt: prompt, model: model, systemPrompt: systemPrompt, conversation: conversation, imageData: imageData))
        let script = scripts.isEmpty ? [.textDelta("unscripted"), .done(GenerationStats(totalDuration: 0))] : scripts.removeFirst()
        let chunk = firstChunk
        let stream = AsyncStream<StreamEvent> { continuation in
            guard let script else {
                continuation.yield(.textDelta(chunk))
                return   // never finishes; ends when the consumer is cancelled
            }
            for event in script { continuation.yield(event) }
            continuation.finish()
        }
        return (UUID(), stream)
    }
}
