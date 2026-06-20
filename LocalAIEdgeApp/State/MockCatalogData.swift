import Foundation

enum MockCatalogData {

    // MARK: - Model Catalog
    // App Store catalog: keep only models with green working status in this app runtime.

    static let items: [ModelCatalogItem] = [
        ModelCatalogItem(
            displayName: "Apple Intelligence",
            family: .appleIntelligence,
            provider: .localFile,
            variant: "System Foundation Model",
            summary: "Apple's on-device Foundation Models runtime. Uses the system Apple Intelligence language model when available; no separate model weights are downloaded by this app.",
            parameterSize: "~3B system model",
            quantization: "System managed",
            diskSize: "System managed",
            contextWindow: "System",
            runtimeType: .foundationModels,
            supportsReasoning: true,
            supportsToolCalling: false,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .pro
        ),

        ModelCatalogItem(
            displayName: "Granite 3.3 2B Instruct (MLX)",
            family: .granite,
            variant: "4-bit MLX",
            summary: "IBM Granite 3.3 instruct model converted by MLX Community. Text-only local chat model with Apache 2.0 licensing and a practical memory footprint for iPhone.",
            parameterSize: "2B",
            quantization: "MLX 4-bit",
            diskSize: "~1.4 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/granite-3.3-2b-instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .standard
        ),

        ModelCatalogItem(
            displayName: "Qwen 3.5 VL 0.8B (MLX)",
            family: .qwen,
            variant: "4-bit MLX · Vision",
            summary: "Compact Qwen 3.5 vision-language model. Image input passed the iPhone 17 Pro vision probe with the VLM-safe generation path.",
            parameterSize: "0.8B",
            quantization: "MLX 4-bit",
            diskSize: "~1.0 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3.5-0.8B-4bit",
            sourceSupportsVision: true,
            supportsVision: true,
            supportsToolCalling: true,
            recommendedForIPhone: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .pro
        ),
        ModelCatalogItem(
            displayName: "Qwen 3.5 VL 4B (MLX)",
            family: .qwen,
            variant: "4-bit MLX · Vision",
            summary: "Qwen 3.5 4B vision-language model for stronger image and document understanding on recent iPhones.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~3.0 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3.5-4B-4bit",
            sourceSupportsVision: true,
            supportsVision: true,
            supportsToolCalling: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .pro
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Ultra-compact Qwen 3 text model on Apple Silicon. Native thinking with a small memory footprint for fast on-device chat.",
            parameterSize: "0.6B",
            quantization: "MLX 4-bit",
            diskSize: "~0.6 GB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-0.6B-4bit",
            supportsReasoning: true,
            isThinkingModel: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .compact
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 1.7B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Compact Qwen 3 text model on Apple Silicon. Good balance of speed and quality for local chat with native thinking.",
            parameterSize: "1.7B",
            quantization: "MLX 4-bit",
            diskSize: "~1.7 GB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-1.7B-4bit",
            supportsReasoning: true,
            isThinkingModel: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .standard
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 4B 2507 Instruct (GGUF)",
            family: .qwen,
            variant: "Q4_K_M GGUF · Latest",
            summary: "Latest Qwen 3 4B instruct release for the llama.cpp lane. Text-only on this runtime path, but aligned for tool calling and long-context local chat.",
            parameterSize: "4B",
            quantization: "GGUF Q4_K_M",
            diskSize: "~2.5 GB",
            contextWindow: "256K",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf?download=true"),
            runtimeType: .gguf,
            supportsReasoning: true,
            supportsToolCalling: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            minimumTier: .pro
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 4B 2507 Thinking (GGUF)",
            family: .qwen,
            variant: "Q4_K_M GGUF · Latest",
            summary: "Latest Qwen 3 4B thinking release for the llama.cpp lane. Ideal when you want newer reasoning behavior without leaving the on-device GGUF path.",
            parameterSize: "4B",
            quantization: "GGUF Q4_K_M",
            diskSize: "~2.5 GB",
            contextWindow: "256K",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q4_K_M.gguf?download=true"),
            runtimeType: .gguf,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            minimumTier: .pro
        ),

        ModelCatalogItem(
            displayName: "LFM2.5 VL 1.6B (MLX)",
            family: .lfm,
            variant: "4-bit MLX · Vision",
            summary: "Liquid LFM2.5 vision-language model. Image input passed the iPhone 17 Pro vision probe.",
            parameterSize: "1.6B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-VL-1.6B-4bit",
            sourceSupportsVision: true,
            supportsVision: true,
            supportsToolCalling: true,
            recommendedForIPhone: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .pro
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 350M (MLX)",
            family: .lfm,
            variant: "6-bit MLX · Latest",
            summary: "Latest lightweight LFM2.5 release optimized for low-memory edge instruction following. Uses the LFM ChatML prompt path in this app.",
            parameterSize: "350M",
            quantization: "MLX 6-bit",
            diskSize: "~0.4 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-350M-6bit",
            recommendedForIPhone: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .compact
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 1.2B Thinking (MLX)",
            family: .lfm,
            variant: "6-bit MLX · Latest",
            summary: "Latest LFM2.5 reasoning-focused release for on-device planning and deeper local reasoning.",
            parameterSize: "1.2B",
            quantization: "MLX 6-bit",
            diskSize: "~1.0 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-1.2B-Thinking-6bit",
            supportsReasoning: true,
            isThinkingModel: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .standard
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 1.2B Instruct (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid Foundation 2.5 text-only model on Apple Silicon. Optimized for chat, instruction following, RAG, and tool-calling tasks.",
            parameterSize: "1.2B",
            quantization: "MLX 4-bit",
            diskSize: "~0.7 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
            supportsToolCalling: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .standard
        ),
    ]

    static let installedModels: [InstalledModel] = []

    static let citations: [SearchCitation] = [
        SearchCitation(
            title: "Example source",
            url: URL(string: "https://example.com/live-source")!,
            snippet: "Fresh web context should be clearly separated from local model output."
        )
    ]

    static let sessions: [ChatSession] = []

    // MARK: - All unique labs for filtering
    static let allLabs: [String] = {
        var seen = Set<String>()
        var labs: [String] = []
        for item in items {
            let lab = item.family.lab
            if !seen.contains(lab) {
                seen.insert(lab)
                labs.append(lab)
            }
        }
        return labs
    }()
}
