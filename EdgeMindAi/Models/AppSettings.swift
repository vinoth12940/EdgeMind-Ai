import Foundation

struct AppSettings: Codable, Hashable {
    var defaultModelID: UUID?
    var systemPrompt: String
    var searchGatewayURL: URL?
    var privacyModeEnabled: Bool
    var useSearchByDefault: Bool
    var voiceModeEnabled: Bool
    var voiceModel: VoiceModel
    var voicePreset: VoicePreset
    var autoPlayVoiceResponses: Bool
    var voiceResponseRate: Double
    var appearanceMode: AppearanceMode

    // Web Search API Configuration
    var webSearchProvider: WebSearchProvider
    var webSearchAPIKey: String

    // HuggingFace Authentication
    var huggingFaceToken: String
    var streamProcessorV2Enabled: Bool
    var inferenceV2Timeout: TimeInterval

    enum VoiceModel: String, Codable, Hashable, CaseIterable {
        case kokoro82M = "Kokoro 82M"

        var catalogDisplayName: String {
            switch self {
            case .kokoro82M:
                return "Kokoro 82M Voice"
            }
        }

        var description: String {
            switch self {
            case .kokoro82M:
                return "Preferred downloadable voice asset for future native MLX speech synthesis. Today, dictation and spoken replies run through Apple's on-device speech services."
            }
        }
    }

    enum VoicePreset: String, Codable, Hashable, CaseIterable {
        case balanced = "Balanced"
        case warm = "Warm"
        case clear = "Clear"
        case energetic = "Energetic"

        var description: String {
            switch self {
            case .balanced:
                return "Neutral voice for everyday replies"
            case .warm:
                return "Softer tone for conversational answers"
            case .clear:
                return "Sharper articulation for facts and instructions"
            case .energetic:
                return "More lively delivery for interactive use"
            }
        }
    }

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

    enum AppearanceMode: String, Codable, Hashable, CaseIterable {
        case system = "System"
        case dark = "Dark"
        case light = "Light"

        var iconName: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .dark: return "moon.fill"
            case .light: return "sun.max.fill"
            }
        }

        var description: String {
            switch self {
            case .system:
                return "Follow the iPhone appearance setting."
            case .dark:
                return "Use the high-contrast dark interface."
            case .light:
                return "Use a bright interface for daylight reading."
            }
        }
    }

    static let `default` = AppSettings(
        defaultModelID: nil,
        systemPrompt: "You are a helpful AI assistant. Answer the user's question directly and accurately. Be concise but thorough. If you are unsure or do not know the answer, say so honestly instead of guessing. Do not repeat the question back. Do not add unnecessary filler or disclaimers. Refuse requests for instructions that enable physical harm, weapon construction, cyber abuse, credential theft, or self-harm methods, and redirect to safety-focused help. When web search results are provided, use them to give current and factual answers, citing sources by number.",
        searchGatewayURL: URL(string: "http://localhost:8787/api/search"),
        privacyModeEnabled: true,
        useSearchByDefault: false,
        voiceModeEnabled: false,
        voiceModel: .kokoro82M,
        voicePreset: .balanced,
        autoPlayVoiceResponses: false,
        voiceResponseRate: 1.0,
        appearanceMode: .system,
        webSearchProvider: .none,
        webSearchAPIKey: "",
        huggingFaceToken: "",
        streamProcessorV2Enabled: true,
        inferenceV2Timeout: 15
    )
}

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case defaultModelID
        case systemPrompt
        case searchGatewayURL
        case privacyModeEnabled
        case useSearchByDefault
        case voiceModeEnabled
        case voiceModel
        case voicePreset
        case autoPlayVoiceResponses
        case voiceResponseRate
        case appearanceMode
        case webSearchProvider
        case webSearchAPIKey
        case huggingFaceToken
        case streamProcessorV2Enabled
        case inferenceV2Timeout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultModelID = try container.decodeIfPresent(UUID.self, forKey: .defaultModelID)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? Self.default.systemPrompt
        searchGatewayURL = try container.decodeIfPresent(URL.self, forKey: .searchGatewayURL)
        privacyModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .privacyModeEnabled) ?? Self.default.privacyModeEnabled
        useSearchByDefault = try container.decodeIfPresent(Bool.self, forKey: .useSearchByDefault) ?? Self.default.useSearchByDefault
        voiceModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceModeEnabled) ?? Self.default.voiceModeEnabled
        voiceModel = try container.decodeIfPresent(VoiceModel.self, forKey: .voiceModel) ?? Self.default.voiceModel
        voicePreset = try container.decodeIfPresent(VoicePreset.self, forKey: .voicePreset) ?? Self.default.voicePreset
        autoPlayVoiceResponses = try container.decodeIfPresent(Bool.self, forKey: .autoPlayVoiceResponses) ?? Self.default.autoPlayVoiceResponses
        voiceResponseRate = try container.decodeIfPresent(Double.self, forKey: .voiceResponseRate) ?? Self.default.voiceResponseRate
        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? Self.default.appearanceMode
        webSearchProvider = try container.decodeIfPresent(WebSearchProvider.self, forKey: .webSearchProvider) ?? Self.default.webSearchProvider
        webSearchAPIKey = try container.decodeIfPresent(String.self, forKey: .webSearchAPIKey) ?? Self.default.webSearchAPIKey
        huggingFaceToken = try container.decodeIfPresent(String.self, forKey: .huggingFaceToken) ?? Self.default.huggingFaceToken
        streamProcessorV2Enabled = try container.decodeIfPresent(Bool.self, forKey: .streamProcessorV2Enabled) ?? true
        inferenceV2Timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .inferenceV2Timeout) ?? 15
    }
}
