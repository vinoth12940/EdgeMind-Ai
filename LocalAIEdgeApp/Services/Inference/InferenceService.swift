import Foundation

protocol InferenceService {
    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?
    ) async throws -> ChatMessage

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data?
    ) async throws -> (messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>)
}

enum InferenceServiceError: LocalizedError {
    case noModelInstalled
    case missingLocalModelFile
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noModelInstalled:
            return "Install a model before starting a chat."
        case .missingLocalModelFile:
            return "The selected model is marked installed, but its local file could not be found."
        case .runtimeUnavailable(let message):
            return message
        }
    }
}
