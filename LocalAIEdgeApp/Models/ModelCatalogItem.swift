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
            }
        }
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
    let supportsVision: Bool
    let supportsReasoning: Bool
    let supportsToolCalling: Bool
    let isThinkingModel: Bool
    let recommendedForIPhone: Bool

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
        self.supportsVision = supportsVision
        self.supportsReasoning = supportsReasoning
        self.supportsToolCalling = supportsToolCalling
        self.isThinkingModel = isThinkingModel
        self.recommendedForIPhone = recommendedForIPhone
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
