import Foundation

enum CoreAIModelCompatibility {
    static let packageURL = URL(string: "https://github.com/apple/coreai-models")!
    static let minimumRuntimePlatform = "iOS 27.0"
    static let minimumXcodeVersion = "Xcode 27.0"

    struct ExportPreset: Equatable {
        let shortName: String
        let huggingFaceID: String
        let compression: String
        let contextTokens: Int
    }

    enum Status: Equatable {
        case directLLMPreset(ExportPreset)
        case relatedLLMPreset(ExportPreset, note: String)
        case systemFoundationModels(note: String)
        case notRegistered(note: String)

        var canUseCoreAIRuntimeInThisBuild: Bool {
            false
        }

        var label: String {
            switch self {
            case .directLLMPreset:
                return "Core AI export preset"
            case .relatedLLMPreset:
                return "Related Core AI preset"
            case .systemFoundationModels:
                return "System Foundation Models"
            case .notRegistered:
                return "No Core AI preset"
            }
        }
    }

    static let iOSLLMPresets: [ExportPreset] = [
        ExportPreset(
            shortName: "qwen3-0.6b",
            huggingFaceID: "Qwen/Qwen3-0.6B",
            compression: "models/qwen3/qwen3_0_6b_mixed_4bit_8bit.yaml",
            contextTokens: 4_096
        ),
        ExportPreset(
            shortName: "qwen2.5-1.5b-instruct",
            huggingFaceID: "Qwen/Qwen2.5-1.5B-Instruct",
            compression: "4bit_weight_palettized_group8",
            contextTokens: 4_096
        ),
        ExportPreset(
            shortName: "qwen3-4b",
            huggingFaceID: "Qwen/Qwen3-4B",
            compression: "models/qwen3/qwen3_4b_mixed_4bit_8bit.yaml",
            contextTokens: 4_096
        )
    ]

    static func status(for item: ModelCatalogItem) -> Status {
        if item.runtimeType == .foundationModels {
            return .systemFoundationModels(
                note: "This uses Apple's system Foundation Models API, not an exported .aimodel from apple/coreai-models."
            )
        }

        guard let catalogSourceID = catalogSourceID(for: item) else {
            return .notRegistered(note: "The model has no Hugging Face source ID that matches Apple's Core AI model registry.")
        }

        let normalizedSourceID = normalize(catalogSourceID)
        if let preset = iOSLLMPresets.first(where: { normalize($0.huggingFaceID) == normalizedSourceID }) {
            return .directLLMPreset(preset)
        }

        if normalizedSourceID == "qwen306b" {
            return .directLLMPreset(iOSLLMPresets[0])
        }

        if item.displayName.contains("Qwen 3 4B") {
            return .relatedLLMPreset(
                iOSLLMPresets[2],
                note: "Apple registers Qwen/Qwen3-4B for iOS Core AI export. This catalog item is a newer 2507 Instruct/Thinking GGUF variant, so it must stay on llama.cpp until exported and audited separately."
            )
        }

        return .notRegistered(note: "\(catalogSourceID) is not in Apple's published iOS LLM presets.")
    }

    static func allStatuses(for items: [ModelCatalogItem]) -> [UUID: Status] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, status(for: $0)) })
    }

    private static func catalogSourceID(for item: ModelCatalogItem) -> String? {
        if let mlxModelID = item.mlxModelID {
            return mlxModelID
        }

        guard let downloadURL = item.downloadURL,
              let range = downloadURL.absoluteString.range(
                of: #"huggingface\.co/([^/]+/[^/]+)/"#,
                options: .regularExpression
              )
        else {
            return nil
        }

        let matched = String(downloadURL.absoluteString[range])
        return matched
            .replacingOccurrences(of: "huggingface.co/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "mlx-community/", with: "")
            .replacingOccurrences(of: "-4bit", with: "")
            .replacingOccurrences(of: "-6bit", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }
}
