import Foundation

enum MockCatalogData {

    // MARK: - Model Catalog
    // Curated runnable set: Gemma 4 (GGUF) + Qwen 3/Qwen 3 VL + LFM 2.5 (MLX/GGUF).
    // Capability flags reflect source vs runtime behavior in this app.
    // Capability flags reflect actual model card specs.

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
            supportsToolCalling: true,
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("raiSafety"),
            minimumTier: .pro
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // GOOGLE DEEPMIND — Gemma 4 GGUF
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Gemma 4 E2B (GGUF)",
            family: .gemma,
            variant: "Q4_K_M GGUF",
            summary: "Google Gemma 4 E2B via llama.cpp GGUF runtime. Source model is multimodal, but current GGUF runtime path in this app is text-only.",
            parameterSize: "2B",
            quantization: "GGUF Q4_K_M",
            diskSize: "~1.6 GB",
            contextWindow: "128K",
            downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf?download=true"),
            runtimeType: .gguf,
            sourceSupportsVision: true,
            supportsVision: false,
            supportsReasoning: true,
            supportsToolCalling: false,
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("raiSafety"),
            minimumTier: .standard
        ),
        ModelCatalogItem(
            displayName: "Gemma 4 E4B (GGUF)",
            family: .gemma,
            variant: "Q4_K_M GGUF",
            summary: "Google Gemma 4 E4B via llama.cpp GGUF runtime. Source model is multimodal, but current GGUF runtime path in this app is text-only.",
            parameterSize: "4B",
            quantization: "GGUF Q4_K_M",
            diskSize: "~2.6 GB",
            contextWindow: "128K",
            downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true"),
            runtimeType: .gguf,
            sourceSupportsVision: true,
            supportsVision: false,
            supportsReasoning: true,
            supportsToolCalling: false,
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("raiSafety"),
            minimumTier: .pro
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // IBM — Granite MLX
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
            recommendedForIPhone: true,
            runtimeStatus: .recommended,
            auditVerdict: .green,
            testedDeviceTier: .pro,
            minimumTier: .standard
        ),
        ModelCatalogItem(
            displayName: "Granite 3.3 8B Instruct (MLX)",
            family: .granite,
            variant: "4-bit MLX",
            summary: "Larger IBM Granite 3.3 instruct model converted by MLX Community. Better quality than the 2B variant, but only suitable for high-memory devices.",
            parameterSize: "8B",
            quantization: "MLX 4-bit",
            diskSize: "~4.6 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/granite-3.3-8b-instruct-4bit",
            supportsReasoning: true,
            runtimeStatus: .unsupported,
            minimumTier: .ultra
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // ALIBABA CLOUD — Qwen 3 MLX
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Qwen 3 VL 4B (MLX)",
            family: .qwen,
            variant: "4-bit MLX · Vision",
            summary: "Qwen 3 vision-language model for reliable image + text understanding on the bundled MLX runtime.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~4.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-VL-4B-Instruct-4bit",
            supportsVision: true,
            runtimeStatus: .experimental,
            auditVerdict: .red("signal-9-memory"),
            minimumTier: .ultra
        ),
        ModelCatalogItem(
            displayName: "Qwen 3.5 VL 0.8B (MLX)",
            family: .qwen,
            variant: "4-bit MLX · Vision",
            summary: "Compact Qwen 3.5 vision-language model. Upstream supports image input, but the current MLX Swift runtime hits a fatal shape error during image generation, so image input is blocked in this app build.",
            parameterSize: "0.8B",
            quantization: "MLX 4-bit",
            diskSize: "~1.0 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3.5-0.8B-4bit",
            sourceSupportsVision: true,
            supportsVision: false,
            runtimeStatus: .unsupported,
            auditVerdict: .red("mlx-swift-lm-qwen35-vlm-shape-crash"),
            minimumTier: .pro
        ),
        ModelCatalogItem(
            displayName: "Qwen 3.5 VL 4B (MLX)",
            family: .qwen,
            variant: "4-bit MLX · Vision",
            summary: "Qwen 3.5 4B vision-language model. Upstream supports image input, but the current MLX Swift runtime hits a fatal shape error during Qwen 3.5 VLM generation, so image input is blocked in this app build.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~3.0 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3.5-4B-4bit",
            sourceSupportsVision: true,
            supportsVision: false,
            runtimeStatus: .unsupported,
            auditVerdict: .red("mlx-swift-lm-qwen35-vlm-shape-crash"),
            minimumTier: .ultra
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Ultra-compact Qwen 3 text model on Apple Silicon. Native thinking (<think> blocks) with a small memory footprint for fast on-device chat.",
            parameterSize: "0.6B",
            quantization: "MLX 4-bit",
            diskSize: "~0.6 GB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-0.6B-4bit",
            supportsReasoning: true,
            isThinkingModel: true,
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("longConversation"),
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
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("raiSafety"),
            minimumTier: .standard
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 4B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Best-value Qwen 3 text model on Apple Silicon. Stronger reasoning than the smaller variants while still fitting on modern iPhones.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~2.5 GB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-4B-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            minimumTier: .ultra
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 4B 2507 Instruct (MLX)",
            family: .qwen,
            variant: "4-bit MLX · Latest",
            summary: "Latest Qwen 3 4B non-thinking release converted by MLX Community. Stronger instruction following, tool use, and 256K long-context support in a device-friendly 4-bit package.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~2.3 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            minimumTier: .ultra
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 4B 2507 Thinking (MLX)",
            family: .qwen,
            variant: "4-bit MLX · Latest",
            summary: "Latest Qwen 3 4B thinking release converted by MLX Community. Best local reasoning lane in the shipped MLX catalog with 256K context and native thinking output.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~2.3 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-4B-Thinking-2507-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            minimumTier: .ultra
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 8B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Most capable Qwen 3 text model in the app. Best on higher-memory devices for more capable local reasoning and longer responses.",
            parameterSize: "8B",
            quantization: "MLX 4-bit",
            diskSize: "~5.5 GB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-8B-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            minimumTier: .ultra
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 4B 2507 Instruct (GGUF)",
            family: .qwen,
            variant: "Q4_K_M GGUF · Latest",
            summary: "Latest Qwen 3 4B instruct release for the llama.cpp lane. Text-only on this runtime path, but better aligned for tool calling and long-context local chat.",
            parameterSize: "4B",
            quantization: "GGUF Q4_K_M",
            diskSize: "~2.5 GB",
            contextWindow: "256K",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf?download=true"),
            runtimeType: .gguf,
            supportsReasoning: true,
            supportsToolCalling: true,
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("raiSafety"),
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
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("toolProbe"),
            minimumTier: .pro
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // LIQUID AI — LFM 2.5 MLX
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "LFM2.5 VL 1.6B (MLX)",
            family: .lfm,
            variant: "4-bit MLX · Vision",
            summary: "Liquid LFM2.5 vision-language model. Upstream supports image input, but the current MLX Swift runtime hits a fatal shape error during image generation, so image input is blocked in this app build.",
            parameterSize: "1.6B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-VL-1.6B-4bit",
            sourceSupportsVision: true,
            supportsVision: false,
            runtimeStatus: .unsupported,
            auditVerdict: .red("mlx-swift-lm-lfm25-vlm-shape-crash"),
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
            summary: "Latest LFM2.5 reasoning-focused release for on-device chain-of-thought style workloads and deeper local planning.",
            parameterSize: "1.2B",
            quantization: "MLX 6-bit",
            diskSize: "~1.0 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-1.2B-Thinking-6bit",
            supportsReasoning: true,
            isThinkingModel: true,
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("longConversation"),
            minimumTier: .standard
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 1.2B Instruct (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid Foundation 2.5 text-only model on Apple Silicon. Optimized for chat, instruction following, RAG, and tool-calling tasks. 32K context.",
            parameterSize: "1.2B",
            quantization: "MLX 4-bit",
            diskSize: "~0.7 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
            runtimeStatus: .worksWithWarnings,
            auditVerdict: .red("toolProbe"),
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
