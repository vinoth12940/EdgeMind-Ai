import CommonCrypto
import Foundation

struct ModelCatalogItem: Identifiable, Hashable, Codable {
    enum ModelFamily: String, Codable, CaseIterable, Hashable {
        case gemma = "Gemma"
        case llama = "Llama"
        case qwen = "Qwen"
        case phi = "Phi"
        case mistral = "Mistral"
        case deepSeek = "DeepSeek"
        case smolLM = "SmolLM"
        case smolVLM = "SmolVLM"
        case stableLM = "StableLM"
        case openELM = "OpenELM"
        case tinyLlama = "TinyLlama"
        case lfm = "LFM"
        case kokoro = "Kokoro"

        var lab: String {
            switch self {
            case .gemma: return "Google DeepMind"
            case .llama: return "Meta"
            case .qwen: return "Alibaba Cloud"
            case .phi: return "Microsoft"
            case .mistral: return "Mistral AI"
            case .deepSeek: return "DeepSeek"
            case .smolLM, .smolVLM: return "Hugging Face"
            case .stableLM: return "Stability AI"
            case .openELM: return "Apple"
            case .tinyLlama: return "StatNLP"
            case .lfm: return "Liquid AI"
            case .kokoro: return "Hexgrad / MLX Community"
            }
        }

        var labIcon: String {
            switch self {
            case .gemma: return "brain.head.profile"
            case .llama: return "bolt.fill"
            case .qwen: return "cloud.fill"
            case .phi: return "square.grid.3x3.fill"
            case .mistral: return "wind"
            case .deepSeek: return "magnifyingglass"
            case .smolLM, .smolVLM: return "face.smiling"
            case .stableLM: return "waveform"
            case .openELM: return "apple.logo"
            case .tinyLlama: return "hare.fill"
            case .lfm: return "drop.fill"
            case .kokoro: return "waveform.path"
            }
        }
    }

    enum PrimaryUse: String, Codable, Hashable {
        case chat
        case voice
    }

    enum SourceProvider: String, Codable, CaseIterable, Hashable {
        case huggingFace = "Hugging Face"
        case modelScope = "ModelScope"
        case directURL = "Direct URL"
        case localFile = "Local File"
    }

    enum RuntimeType: String, Codable, Hashable {
        case gguf = "GGUF"
        case mlx = "MLX"

        var label: String {
            switch self {
            case .gguf: return "llama.cpp"
            case .mlx: return "MLX"
            }
        }

        var icon: String {
            switch self {
            case .gguf: return "cpu"
            case .mlx: return "apple.logo"
            }
        }
    }

    let id: UUID
    let displayName: String
    let family: ModelFamily
    let provider: SourceProvider
    let variant: String
    let summary: String
    let parameterSize: String
    let quantization: String
    let diskSize: String
    let contextWindow: String
    let downloadURL: URL?
    let runtimeType: RuntimeType
    let mlxModelID: String?
    let primaryUse: PrimaryUse
    let supportsVision: Bool
    let supportsReasoning: Bool
    let supportsToolCalling: Bool
    let isThinkingModel: Bool
    let recommendedForIPhone: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case family
        case provider
        case variant
        case summary
        case parameterSize
        case quantization
        case diskSize
        case contextWindow
        case downloadURL
        case runtimeType
        case mlxModelID
        case primaryUse
        case supportsVision
        case supportsReasoning
        case supportsToolCalling
        case isThinkingModel
        case recommendedForIPhone
    }

    init(
        id: UUID? = nil,
        displayName: String,
        family: ModelFamily,
        provider: SourceProvider = .huggingFace,
        variant: String,
        summary: String,
        parameterSize: String,
        quantization: String = "GGUF Q4_K_M",
        diskSize: String,
        contextWindow: String = "4K",
        downloadURL: URL? = nil,
        runtimeType: RuntimeType = .gguf,
        mlxModelID: String? = nil,
        primaryUse: PrimaryUse = .chat,
        supportsVision: Bool = false,
        supportsReasoning: Bool = false,
        supportsToolCalling: Bool = false,
        isThinkingModel: Bool = false,
        recommendedForIPhone: Bool = false
    ) {
        self.id = id ?? Self.deterministicID(displayName: displayName, variant: variant)
        self.displayName = displayName
        self.family = family
        self.provider = provider
        self.variant = variant
        self.summary = summary
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.diskSize = diskSize
        self.contextWindow = contextWindow
        self.downloadURL = downloadURL
        self.runtimeType = runtimeType
        self.mlxModelID = mlxModelID
        self.primaryUse = primaryUse
        self.supportsVision = supportsVision
        self.supportsReasoning = supportsReasoning
        self.supportsToolCalling = supportsToolCalling
        self.isThinkingModel = isThinkingModel
        self.recommendedForIPhone = recommendedForIPhone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        family = try container.decode(ModelFamily.self, forKey: .family)
        provider = try container.decode(SourceProvider.self, forKey: .provider)
        variant = try container.decode(String.self, forKey: .variant)
        summary = try container.decode(String.self, forKey: .summary)
        parameterSize = try container.decode(String.self, forKey: .parameterSize)
        quantization = try container.decode(String.self, forKey: .quantization)
        diskSize = try container.decode(String.self, forKey: .diskSize)
        contextWindow = try container.decode(String.self, forKey: .contextWindow)
        downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
        runtimeType = try container.decode(RuntimeType.self, forKey: .runtimeType)
        mlxModelID = try container.decodeIfPresent(String.self, forKey: .mlxModelID)
        primaryUse = try container.decodeIfPresent(PrimaryUse.self, forKey: .primaryUse) ?? .chat
        supportsVision = try container.decode(Bool.self, forKey: .supportsVision)
        supportsReasoning = try container.decode(Bool.self, forKey: .supportsReasoning)
        supportsToolCalling = try container.decode(Bool.self, forKey: .supportsToolCalling)
        isThinkingModel = try container.decode(Bool.self, forKey: .isThinkingModel)
        recommendedForIPhone = try container.decode(Bool.self, forKey: .recommendedForIPhone)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(family, forKey: .family)
        try container.encode(provider, forKey: .provider)
        try container.encode(variant, forKey: .variant)
        try container.encode(summary, forKey: .summary)
        try container.encode(parameterSize, forKey: .parameterSize)
        try container.encode(quantization, forKey: .quantization)
        try container.encode(diskSize, forKey: .diskSize)
        try container.encode(contextWindow, forKey: .contextWindow)
        try container.encodeIfPresent(downloadURL, forKey: .downloadURL)
        try container.encode(runtimeType, forKey: .runtimeType)
        try container.encodeIfPresent(mlxModelID, forKey: .mlxModelID)
        try container.encode(primaryUse, forKey: .primaryUse)
        try container.encode(supportsVision, forKey: .supportsVision)
        try container.encode(supportsReasoning, forKey: .supportsReasoning)
        try container.encode(supportsToolCalling, forKey: .supportsToolCalling)
        try container.encode(isThinkingModel, forKey: .isThinkingModel)
        try container.encode(recommendedForIPhone, forKey: .recommendedForIPhone)
    }

    var downloadFileName: String? {
        downloadURL?.lastPathComponent.removingPercentEncoding
    }

    /// Generate a stable UUID from displayName + variant so IDs survive across launches.
    private static func deterministicID(displayName: String, variant: String) -> UUID {
        // UUID v5 using a fixed namespace
        let namespace = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        return uuidV5(namespace: namespace, name: "\(displayName)::\(variant)")
    }

    private static func uuidV5(namespace: UUID, name: String) -> UUID {
        var namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let nameBytes = Array(name.utf8)
        var data = namespaceBytes + nameBytes
        // SHA-1 hash (only need first 16 bytes for UUID)
        var hash = [UInt8](repeating: 0, count: 20)
        data.withUnsafeBufferPointer { ptr in
            var ctx = CC_SHA1_CTX()
            CC_SHA1_Init(&ctx)
            CC_SHA1_Update(&ctx, ptr.baseAddress, CC_LONG(ptr.count))
            CC_SHA1_Final(&hash, &ctx)
        }
        // Set version (5) and variant bits
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3],
                           hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11],
                           hash[12], hash[13], hash[14], hash[15]))
    }

    var capabilities: [ModelCapability] {
        var caps: [ModelCapability] = []
        if isThinkingModel { caps.append(.thinking) }
        if supportsVision { caps.append(.vision) }
        if supportsToolCalling { caps.append(.toolCalling) }
        if supportsReasoning { caps.append(.reasoning) }
        return caps
    }

    enum ModelCapability: String, CaseIterable {
        case thinking = "Think"
        case vision = "Vision"
        case toolCalling = "Tools"
        case reasoning = "Reason"

        var icon: String {
            switch self {
            case .thinking: return "brain"
            case .vision: return "eye.fill"
            case .toolCalling: return "wrench.and.screwdriver.fill"
            case .reasoning: return "lightbulb.fill"
            }
        }
    }
}
