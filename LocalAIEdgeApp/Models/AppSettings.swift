import Foundation

struct AppSettings: Codable, Hashable {
    var defaultModelID: UUID?
    var systemPrompt: String
    var searchGatewayURL: URL?
    var privacyModeEnabled: Bool
    var useSearchByDefault: Bool
    var voiceModeEnabled: Bool

    // Web Search API Configuration
    var webSearchProvider: WebSearchProvider
    var webSearchAPIKey: String

    // HuggingFace Authentication
    var huggingFaceToken: String

    enum WebSearchProvider: String, Codable, Hashable, CaseIterable {
        case none = "None"
        case tavily = "Tavily"
        case brave = "Brave Search"
        case serper = "Serper"
        case custom = "Custom Gateway"

        var placeholder: String {
            switch self {
            case .none: return ""
            case .tavily: return "tvly-xxxxxxxxxxxxxxxxxx"
            case .brave: return "BSAxxxxxxxxxxxxxxxxxx"
            case .serper: return "xxxxxxxxxxxxxxxxxxxxxxxx"
            case .custom: return "Configure gateway URL below"
            }
        }

        var description: String {
            switch self {
            case .none: return "Web search disabled"
            case .tavily: return "AI-optimized search API with structured results"
            case .brave: return "Privacy-focused web search with snippets"
            case .serper: return "Google Search results via API"
            case .custom: return "Your own search gateway endpoint"
            }
        }
    }

    static let `default` = AppSettings(
        defaultModelID: nil,
        systemPrompt: "You are a helpful AI assistant. Answer the user's question directly and accurately. Be concise but thorough. If you are unsure or do not know the answer, say so honestly instead of guessing. Do not repeat the question back. Do not add unnecessary filler or disclaimers. When web search results are provided, use them to give current and factual answers, citing sources by number.",
        searchGatewayURL: URL(string: "http://localhost:8787"),
        privacyModeEnabled: true,
        useSearchByDefault: false,
        voiceModeEnabled: false,
        webSearchProvider: .none,
        webSearchAPIKey: "",
        huggingFaceToken: ""
    )
}
