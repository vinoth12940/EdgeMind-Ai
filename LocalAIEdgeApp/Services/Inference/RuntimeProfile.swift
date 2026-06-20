// LocalAIEdgeApp/Services/Inference/RuntimeProfile.swift
import Foundation

enum ThinkFormat: String, Codable, Hashable {
    case xmlThink      // <think>...</think>, <thinking>..., <reasoning>...
    case qwenNative    // <|im_start|>think ... <|im_end|> or <|think|>...<|/think|>
    case gemmaChannel  // <|channel>thought\n ... <|channel> (GGUF Gemma 4; dead code today)
}

enum ToolCallFormat: String, Codable {
    case xmlToolCall          // <tool_call>{...}</tool_call>
    case gemmaNativeToolCall  // <|tool_call>...<tool_call|>
    case liquidToolCall       // <|tool_call_start|>...<|tool_call_end|>
}

enum VisionMode: String, Codable {
    case none
    case textOnlyInputs   // model accepts images but app routes text-only
    case imageAndText     // model accepts images and app supports attachments
}

enum RuntimeInputMode: String, Codable, Hashable, CaseIterable {
    case text
    case image
    case document
    case audio
}

enum Verdict: Codable, Equatable, Hashable {
    case green
    case yellow(String)
    case red(String)

    private enum CodingKeys: String, CodingKey { case kind, note }
    private enum Kind: String, Codable { case green, yellow, red }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        switch kind {
        case .green:  self = .green
        case .yellow: self = .yellow(note)
        case .red:    self = .red(note)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .green:
            try c.encode(Kind.green, forKey: .kind)
        case .yellow(let note):
            try c.encode(Kind.yellow, forKey: .kind)
            try c.encode(note, forKey: .note)
        case .red(let note):
            try c.encode(Kind.red, forKey: .kind)
            try c.encode(note, forKey: .note)
        }
    }

    var isGreen: Bool { if case .green = self { return true }; return false }
    var isRed: Bool { if case .red = self { return true }; return false }
}

struct RuntimeProfile: Codable, Equatable {
    let catalogID: UUID
    let verifiedThinking: ThinkFormat?
    let verifiedToolCalling: ToolCallFormat?
    let verifiedVision: VisionMode
    let verifiedInputModes: [RuntimeInputMode]
    let knownLeakTokens: [String]
    let recommendedMaxTokens: Int
    let auditedAt: String   // ISO-8601
    let auditVerdict: Verdict
    let lastAuditedDeviceTier: DeviceTier?
    let lastCrashSignal: Int?

    private enum CodingKeys: String, CodingKey {
        case catalogID
        case verifiedThinking
        case verifiedToolCalling
        case verifiedVision
        case verifiedInputModes
        case knownLeakTokens
        case recommendedMaxTokens
        case auditedAt
        case auditVerdict
        case lastAuditedDeviceTier
        case lastCrashSignal
    }

    init(
        catalogID: UUID,
        verifiedThinking: ThinkFormat?,
        verifiedToolCalling: ToolCallFormat?,
        verifiedVision: VisionMode,
        verifiedInputModes: [RuntimeInputMode]? = nil,
        knownLeakTokens: [String],
        recommendedMaxTokens: Int,
        auditedAt: String,
        auditVerdict: Verdict,
        lastAuditedDeviceTier: DeviceTier? = nil,
        lastCrashSignal: Int? = nil
    ) {
        self.catalogID = catalogID
        self.verifiedThinking = verifiedThinking
        self.verifiedToolCalling = verifiedToolCalling
        self.verifiedVision = verifiedVision
        self.verifiedInputModes = verifiedInputModes ?? (verifiedVision == .imageAndText ? [.text, .image, .document] : [.text, .document])
        self.knownLeakTokens = knownLeakTokens
        self.recommendedMaxTokens = recommendedMaxTokens
        self.auditedAt = auditedAt
        self.auditVerdict = auditVerdict
        self.lastAuditedDeviceTier = lastAuditedDeviceTier
        self.lastCrashSignal = lastCrashSignal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogID = try container.decode(UUID.self, forKey: .catalogID)
        verifiedThinking = try container.decodeIfPresent(ThinkFormat.self, forKey: .verifiedThinking)
        verifiedToolCalling = try container.decodeIfPresent(ToolCallFormat.self, forKey: .verifiedToolCalling)
        verifiedVision = try container.decodeIfPresent(VisionMode.self, forKey: .verifiedVision) ?? .none
        verifiedInputModes = try container.decodeIfPresent([RuntimeInputMode].self, forKey: .verifiedInputModes)
            ?? (verifiedVision == .imageAndText ? [.text, .image, .document] : [.text, .document])
        knownLeakTokens = try container.decodeIfPresent([String].self, forKey: .knownLeakTokens) ?? []
        recommendedMaxTokens = try container.decodeIfPresent(Int.self, forKey: .recommendedMaxTokens) ?? 512
        auditedAt = try container.decodeIfPresent(String.self, forKey: .auditedAt) ?? ""
        auditVerdict = try container.decodeIfPresent(Verdict.self, forKey: .auditVerdict) ?? .yellow("legacy-profile")
        lastAuditedDeviceTier = try container.decodeIfPresent(DeviceTier.self, forKey: .lastAuditedDeviceTier)
        lastCrashSignal = try container.decodeIfPresent(Int.self, forKey: .lastCrashSignal)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(catalogID, forKey: .catalogID)
        try container.encodeIfPresent(verifiedThinking, forKey: .verifiedThinking)
        try container.encodeIfPresent(verifiedToolCalling, forKey: .verifiedToolCalling)
        try container.encode(verifiedVision, forKey: .verifiedVision)
        try container.encode(verifiedInputModes, forKey: .verifiedInputModes)
        try container.encode(knownLeakTokens, forKey: .knownLeakTokens)
        try container.encode(recommendedMaxTokens, forKey: .recommendedMaxTokens)
        try container.encode(auditedAt, forKey: .auditedAt)
        try container.encode(auditVerdict, forKey: .auditVerdict)
        try container.encodeIfPresent(lastAuditedDeviceTier, forKey: .lastAuditedDeviceTier)
        try container.encodeIfPresent(lastCrashSignal, forKey: .lastCrashSignal)
    }

    /// Fallback when a model has no profile on file.
    /// Conservative: text-only, no tools, no think-block parsing, strict scrubber.
    static func safeMinimum(catalogID: UUID) -> RuntimeProfile {
        RuntimeProfile(
            catalogID: catalogID,
            verifiedThinking: nil,
            verifiedToolCalling: nil,
            verifiedVision: .none,
            knownLeakTokens: ["<|im_end|>", "<|endoftext|>", "<end_of_turn>"],
            recommendedMaxTokens: 512,
            auditedAt: "",
            auditVerdict: .yellow("no-profile-on-file")
        )
    }
}
