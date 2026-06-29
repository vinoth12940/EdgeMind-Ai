import CommonCrypto
import Foundation

struct ModelCatalogItem: Identifiable, Hashable, Codable {
    enum ModelRuntimeStatus: String, Codable, CaseIterable, Hashable {
        case recommended
        case worksWithWarnings
        case experimental
        case unsupported

        var label: String {
            switch self {
            case .recommended: return "Recommended"
            case .worksWithWarnings: return "Works with warnings"
            case .experimental: return "Experimental"
            case .unsupported: return "Unsupported on this phone"
            }
        }
    }

    enum ModelFamily: String, Codable, CaseIterable, Hashable {
        case gemma = "Gemma"
        case granite = "Granite"
        case llama = "Llama"
        case qwen = "Qwen"
        case phi = "Phi"
        case mistral = "Mistral"
        case deepSeek = "DeepSeek"
        case smolLM = "SmolLM"
        case smolVLM = "SmolVLM"
        case stableLM = "StableLM"
        case openELM = "OpenELM"
        case appleIntelligence = "Apple Intelligence"
        case tinyLlama = "TinyLlama"
        case lfm = "LFM"
        case kokoro = "Kokoro"
        case mlxCommunity = "MLX Community"

        var lab: String {
            switch self {
            case .gemma: return "Google DeepMind"
            case .granite: return "IBM"
            case .llama: return "Meta"
            case .qwen: return "Alibaba Cloud"
            case .phi: return "Microsoft"
            case .mistral: return "Mistral AI"
            case .deepSeek: return "DeepSeek"
            case .smolLM, .smolVLM: return "Hugging Face"
            case .stableLM: return "Stability AI"
            case .openELM, .appleIntelligence: return "Apple"
            case .tinyLlama: return "StatNLP"
            case .lfm: return "Liquid AI"
            case .kokoro: return "Hexgrad / MLX Community"
            case .mlxCommunity: return "MLX Community"
            }
        }

        var labIcon: String {
            switch self {
            case .gemma: return "brain.head.profile"
            case .granite: return "building.columns.fill"
            case .llama: return "bolt.fill"
            case .qwen: return "cloud.fill"
            case .phi: return "square.grid.3x3.fill"
            case .mistral: return "wind"
            case .deepSeek: return "magnifyingglass"
            case .smolLM, .smolVLM: return "face.smiling"
            case .stableLM: return "waveform"
            case .openELM: return "apple.logo"
            case .appleIntelligence: return "apple.intelligence"
            case .tinyLlama: return "hare.fill"
            case .lfm: return "drop.fill"
            case .kokoro: return "waveform.path"
            case .mlxCommunity: return "shippingbox.fill"
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
        case liteRTLM = "LiteRTLM"
        case foundationModels = "FoundationModels"

        var label: String {
            switch self {
            case .gguf: return "llama.cpp"
            case .mlx: return "MLX"
            case .liteRTLM: return "LiteRT-LM"
            case .foundationModels: return "Apple Intelligence"
            }
        }

        var icon: String {
            switch self {
            case .gguf: return "cpu"
            case .mlx: return "apple.logo"
            case .liteRTLM: return "bolt.badge.automatic"
            case .foundationModels: return "apple.intelligence"
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
    let sourceSupportsVision: Bool
    let sourceSupportsVideo: Bool
    let sourceSupportsAudio: Bool
    let supportsVision: Bool
    let supportsReasoning: Bool
    let supportsToolCalling: Bool
    let isThinkingModel: Bool
    let recommendedForIPhone: Bool
    let minimumTier: DeviceTier
    let runtimeStatus: ModelRuntimeStatus
    let auditVerdict: Verdict
    let testedDeviceTier: DeviceTier?
    let inputModes: [InputCategory]

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
        case sourceSupportsVision
        case sourceSupportsVideo
        case sourceSupportsAudio
        case supportsVision
        case supportsReasoning
        case supportsToolCalling
        case isThinkingModel
        case recommendedForIPhone
        case minimumTier
        case runtimeStatus
        case auditVerdict
        case testedDeviceTier
        case inputModes
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
        sourceSupportsVision: Bool? = nil,
        sourceSupportsVideo: Bool = false,
        sourceSupportsAudio: Bool = false,
        supportsVision: Bool = false,
        supportsReasoning: Bool = false,
        supportsToolCalling: Bool = false,
        isThinkingModel: Bool = false,
        recommendedForIPhone: Bool = false,
        runtimeStatus: ModelRuntimeStatus? = nil,
        auditVerdict: Verdict? = nil,
        testedDeviceTier: DeviceTier? = nil,
        minimumTier: DeviceTier = .standard,
        inputModes: [InputCategory]? = nil
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
        self.sourceSupportsVision = sourceSupportsVision ?? supportsVision
        self.sourceSupportsVideo = sourceSupportsVideo
        self.sourceSupportsAudio = sourceSupportsAudio
        self.supportsVision = supportsVision
        self.supportsReasoning = supportsReasoning
        self.supportsToolCalling = supportsToolCalling
        self.isThinkingModel = isThinkingModel
        self.recommendedForIPhone = recommendedForIPhone
        self.minimumTier = minimumTier
        self.runtimeStatus = runtimeStatus ?? (recommendedForIPhone ? .recommended : .experimental)
        self.auditVerdict = auditVerdict ?? (recommendedForIPhone ? .green : .yellow("not-audited-for-recommendation"))
        self.testedDeviceTier = testedDeviceTier
        self.inputModes = inputModes ?? Self.defaultInputModes(
            primaryUse: primaryUse,
            runtimeType: runtimeType,
            supportsVision: supportsVision
        )
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
        if let sourceVision = try container.decodeIfPresent(Bool.self, forKey: .sourceSupportsVision) {
            sourceSupportsVision = sourceVision
        } else {
            sourceSupportsVision = try container.decode(Bool.self, forKey: .supportsVision)
        }
        sourceSupportsVideo = try container.decodeIfPresent(Bool.self, forKey: .sourceSupportsVideo) ?? false
        sourceSupportsAudio = try container.decodeIfPresent(Bool.self, forKey: .sourceSupportsAudio) ?? false
        supportsVision = try container.decode(Bool.self, forKey: .supportsVision)
        supportsReasoning = try container.decode(Bool.self, forKey: .supportsReasoning)
        supportsToolCalling = try container.decode(Bool.self, forKey: .supportsToolCalling)
        isThinkingModel = try container.decode(Bool.self, forKey: .isThinkingModel)
        recommendedForIPhone = try container.decodeIfPresent(Bool.self, forKey: .recommendedForIPhone) ?? false
        minimumTier = try container.decodeIfPresent(DeviceTier.self, forKey: .minimumTier) ?? .standard
        runtimeStatus = try container.decodeIfPresent(ModelRuntimeStatus.self, forKey: .runtimeStatus)
            ?? (recommendedForIPhone ? .recommended : .experimental)
        auditVerdict = try container.decodeIfPresent(Verdict.self, forKey: .auditVerdict)
            ?? (recommendedForIPhone ? .green : .yellow("not-audited-for-recommendation"))
        testedDeviceTier = try container.decodeIfPresent(DeviceTier.self, forKey: .testedDeviceTier)
        inputModes = try container.decodeIfPresent([InputCategory].self, forKey: .inputModes)
            ?? Self.defaultInputModes(primaryUse: primaryUse, runtimeType: runtimeType, supportsVision: supportsVision)
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
        try container.encode(sourceSupportsVision, forKey: .sourceSupportsVision)
        try container.encode(sourceSupportsVideo, forKey: .sourceSupportsVideo)
        try container.encode(sourceSupportsAudio, forKey: .sourceSupportsAudio)
        try container.encode(supportsVision, forKey: .supportsVision)
        try container.encode(supportsReasoning, forKey: .supportsReasoning)
        try container.encode(supportsToolCalling, forKey: .supportsToolCalling)
        try container.encode(isThinkingModel, forKey: .isThinkingModel)
        try container.encode(recommendedForIPhone, forKey: .recommendedForIPhone)
        try container.encode(minimumTier, forKey: .minimumTier)
        try container.encode(runtimeStatus, forKey: .runtimeStatus)
        try container.encode(auditVerdict, forKey: .auditVerdict)
        try container.encodeIfPresent(testedDeviceTier, forKey: .testedDeviceTier)
        try container.encode(inputModes, forKey: .inputModes)
    }

    var downloadFileName: String? {
        downloadURL?.lastPathComponent.removingPercentEncoding
    }

    var contextWindowTokenCount: Int {
        Self.parseContextWindowTokenCount(contextWindow)
    }

    var isLatestRelease: Bool {
        displayName.localizedCaseInsensitiveContains("2507")
            || mlxModelID?.localizedCaseInsensitiveContains("2507") == true
            || downloadURL?.absoluteString.localizedCaseInsensitiveContains("2507") == true
    }

    var isCommunityDiscoveredMLX: Bool {
        runtimeType == .mlx
            && mlxModelID != nil
            && (variant.hasPrefix("Hugging Face MLX -") || variant.hasPrefix("MLX Community -"))
    }

    /// Generate a stable UUID from displayName + variant so IDs survive across launches.
    private static func deterministicID(displayName: String, variant: String) -> UUID {
        // UUID v5 using a fixed namespace
        let namespace = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        return uuidV5(namespace: namespace, name: "\(displayName)::\(variant)")
    }

    static func parseContextWindowTokenCount(_ rawValue: String) -> Int {
        let compact = rawValue
            .uppercased()
            .replacingOccurrences(of: "TOKENS", with: "")
            .replacingOccurrences(of: "TOKEN", with: "")
            .replacingOccurrences(of: " ", with: "")

        let numericPortion = compact.filter { $0.isNumber || $0 == "." }
        guard let value = Double(numericPortion), value > 0 else { return 0 }

        let multiplier: Double
        if compact.contains("M") {
            multiplier = 1_000_000
        } else if compact.contains("K") {
            multiplier = 1_000
        } else {
            multiplier = 1
        }

        return Int((value * multiplier).rounded())
    }

    private static func uuidV5(namespace: UUID, name: String) -> UUID {
        let namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let nameBytes = Array(name.utf8)
        let data = namespaceBytes + nameBytes
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
        if runtimeInputCategories.contains(.video) { caps.append(.video) }
        if runtimeInputCategories.contains(.audio) { caps.append(.audio) }
        if supportsToolCalling { caps.append(.toolCalling) }
        if supportsReasoning { caps.append(.reasoning) }
        return caps
    }

    enum ModelCapability: String, CaseIterable {
        case thinking = "Think"
        case vision = "Vision"
        case video = "Video"
        case audio = "Audio"
        case toolCalling = "Tools"
        case reasoning = "Reason"

        var icon: String {
            switch self {
            case .thinking: return "brain"
            case .vision: return "eye.fill"
            case .video: return "video.fill"
            case .audio: return "waveform"
            case .toolCalling: return "wrench.and.screwdriver.fill"
            case .reasoning: return "lightbulb.fill"
            }
        }
    }

    enum InputCategory: String, Codable, CaseIterable, Hashable {
        case text = "Text"
        case image = "Image"
        case video = "Video"
        case audio = "Audio"
        case document = "Document"

        var icon: String {
            switch self {
            case .text: return "text.alignleft"
            case .image: return "photo"
            case .video: return "video"
            case .audio: return "waveform"
            case .document: return "doc.text"
            }
        }
    }

    /// Inputs the upstream model family supports (from source/model card intent).
    var sourceInputCategories: [InputCategory] {
        if primaryUse == .voice {
            return [.audio]
        }
        var result: [InputCategory] = [.text]
        if sourceSupportsVision {
            result.append(.image)
        }
        if inputModes.contains(.document) {
            result.append(.document)
        }
        return result
    }

    /// Inputs this app runtime currently accepts for this model.
    var runtimeInputCategories: [InputCategory] {
        if primaryUse == .voice {
            return [.audio]
        }
        return inputModes
    }

    var inputCategoriesDifferByRuntime: Bool {
        sourceInputCategories != runtimeInputCategories
    }

    /// Approximate resident memory (GB) the model will use at runtime.
    /// weights ≈ disk × 1.15  +  KV cache (layer count × head dim × ctx)
    ///         + vision tower (0.6 GB if applicable)  +  app heap headroom (0.3 GB).
    func estimatedResidentGB(contextTokens: Int) -> Double {
        let weightsGB = parsedDiskSizeGBForEstimator * 1.15
        let kvCacheGB = kvCacheEstimateGB(contextTokens: contextTokens)
        let visionGB: Double = supportsVision ? 0.6 : 0.0
        let heapGB = 0.3
        return weightsGB + kvCacheGB + visionGB + heapGB
    }

    var parsedDiskSizeGBForEstimator: Double {
        // diskSize is a string like "~1.7 GB" / "2.5 GB" / "~600 MB".
        let upper = diskSize.uppercased()
        let numericPortion = upper.filter { $0.isNumber || $0 == "." }
        guard let value = Double(numericPortion), value > 0 else { return 0 }
        if upper.contains("MB") { return value / 1024.0 }
        return value
    }

    private func kvCacheEstimateGB(contextTokens: Int) -> Double {
        // Rough family-based estimate. KV cache = 2 × nLayers × nHeads × headDim × ctx × 2 bytes.
        let perTokenKB: Double
        switch parameterSize {
        case _ where parameterSize.contains("0.6"):  perTokenKB = 2
        case _ where parameterSize.contains("1.2"):  perTokenKB = 3
        case _ where parameterSize.contains("1.6"):  perTokenKB = 3
        case _ where parameterSize.contains("1.7"):  perTokenKB = 4
        case _ where parameterSize.contains("2"):    perTokenKB = 5
        case _ where parameterSize.contains("4"):    perTokenKB = 7
        case _ where parameterSize.contains("8"):    perTokenKB = 10
        default:                                      perTokenKB = 4
        }
        return (Double(contextTokens) * perTokenKB) / (1024 * 1024)
    }

    private static func defaultInputModes(
        primaryUse: PrimaryUse,
        runtimeType: RuntimeType,
        supportsVision: Bool
    ) -> [InputCategory] {
        if primaryUse == .voice {
            return [.audio]
        }
        var modes: [InputCategory] = [.text, .document]
        if (runtimeType == .mlx || runtimeType == .liteRTLM) && supportsVision {
            modes.append(.image)
        }
        return modes
    }
}
