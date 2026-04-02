import Foundation

struct MockInferenceService: InferenceService {
    var events: [StreamEvent] = []

    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> ChatMessage {
        try await Task.sleep(for: .milliseconds(350))

        let prefix = searchContext == nil ? "Local model" : "Local model with web context"
        let contextLine = searchContext?.snippets.prefix(2).joined(separator: " ") ?? "No external data was used."
        let reply = "\(prefix) \(model.catalogItem.displayName) says: \(prompt)\n\nSystem prompt: \(systemPrompt)\n\nContext: \(contextLine)"

        return ChatMessage(
            role: .assistant,
            text: reply,
            citations: searchContext?.citations ?? []
        )
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        let messageID = UUID()
        let eventsToEmit: [StreamEvent] = events.isEmpty
            ? [.textDelta("Mock response for: \(prompt)"), .done]
            : events
        let stream = AsyncStream<StreamEvent> { continuation in
            for event in eventsToEmit { continuation.yield(event) }
            continuation.finish()
        }
        return (messageID: messageID, stream: stream)
    }
}
