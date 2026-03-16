import Foundation

struct MockInferenceService: InferenceService {
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
    ) async throws -> (messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>) {
        let message = try await generateReply(
            prompt: prompt,
            model: model,
            conversation: conversation,
            searchContext: searchContext,
            systemPrompt: systemPrompt
        )
        let stream = AsyncStream<String> { continuation in
            continuation.yield(message.text)
            continuation.finish()
        }
        return (messageID: message.id, citations: message.citations, stream: stream)
    }
}
