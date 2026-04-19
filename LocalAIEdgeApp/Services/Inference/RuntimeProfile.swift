// LocalAIEdgeApp/Services/Inference/RuntimeProfile.swift
import Foundation

enum ThinkFormat: String, Codable {
    case xmlThink      // <think>...</think>, <thinking>..., <reasoning>...
    case qwenNative    // <|im_start|>think ... <|im_end|> or <|think|>...<|/think|>
    case gemmaChannel  // <|channel>thought\n ... <|channel> (GGUF Gemma 4; dead code today)
}

enum ToolCallFormat: String, Codable {
    case xmlToolCall          // <tool_call>{...}</tool_call>
    case gemmaNativeToolCall  // <|tool_call>...<tool_call|>
}

enum VisionMode: String, Codable {
    case none
    case textOnlyInputs   // model accepts images but app routes text-only
    case imageAndText     // model accepts images and app supports attachments
}

enum Verdict: Codable, Equatable {
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
    let knownLeakTokens: [String]
    let recommendedMaxTokens: Int
    let auditedAt: String   // ISO-8601
    let auditVerdict: Verdict

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
