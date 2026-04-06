import Foundation

enum MockCatalogData {

    // MARK: - Model Catalog
    // MLX-only testing set: Gemma 3n, Qwen 3.5, LFM 2.5.
    // All models use native Apple Silicon MLX runtime for best iPhone performance.
    // Capability flags reflect actual model card specs.

    static let items: [ModelCatalogItem] = [

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // GOOGLE DEEPMIND — Gemma 3n MLX
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Gemma 3n E2B (MLX)",
            family: .gemma,
            variant: "4-bit MLX",
            summary: "Google Gemma 3n E2B on Apple Silicon. Native MLX multimodal model with text + image input and 32K context.",
            parameterSize: "2B",
            quantization: "MLX 4-bit",
            diskSize: "~3.6 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/gemma-3n-E2B-it-4bit",
            supportsVision: true,
            supportsReasoning: true,
            supportsToolCalling: false,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 3n E4B (MLX)",
            family: .gemma,
            variant: "4-bit MLX",
            summary: "Google Gemma 3n E4B on Apple Silicon. Higher-capacity multimodal model with text + image input and 32K context.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~4.0 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/gemma-3n-E4B-it-4bit",
            supportsVision: true,
            supportsReasoning: true,
            supportsToolCalling: false,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // ALIBABA CLOUD — Qwen 3.5 MLX
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Qwen 3.5 0.8B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Ultra-compact Qwen 3.5 VLM on Apple Silicon. Image + text, thinking (<think> blocks), and tool calling in 0.6 GB. Note: 0.8B is prone to thinking loops.",
            parameterSize: "0.8B",
            quantization: "MLX 4-bit",
            diskSize: "~0.6 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
            supportsVision: true,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 3.5 2B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Compact Qwen 3.5 VLM on Apple Silicon. Image + text, native thinking, and tool calling in 1.7 GB. 256K context.",
            parameterSize: "2B",
            quantization: "MLX 4-bit",
            diskSize: "~1.7 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3.5-2B-MLX-4bit",
            supportsVision: true,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 3.5 4B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Best-value Qwen 3.5 VLM on Apple Silicon. Image + text, thinking, and tool calling. 256K context.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~2.5 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3.5-4B-MLX-4bit",
            supportsVision: true,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 3.5 9B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Most capable Qwen 3.5 VLM on Apple Silicon. Image + text, thinking, and tool calling. Requires 8 GB RAM — best on iPhone 15 Pro Max or iPad Pro. 256K context.",
            parameterSize: "9B",
            quantization: "MLX 4-bit",
            diskSize: "~5.5 GB",
            contextWindow: "256K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3.5-9B-MLX-4bit",
            supportsVision: true,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // LIQUID AI — LFM 2.5 MLX
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "LFM2.5 1.2B Instruct (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid Foundation 2.5 text-only model on Apple Silicon. Optimised for agentic, RAG, and tool-calling tasks. Not suited for knowledge-intensive tasks or code. 32K context.",
            parameterSize: "1.2B",
            quantization: "MLX 4-bit",
            diskSize: "~0.7 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 VL 1.6B (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid vision-language model on Apple Silicon. Image + text via mlx-vlm, tool calling (text-only inputs). Fast inference, real-time caption capable. 32K context.",
            parameterSize: "1.6B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-VL-1.6B-4bit",
            supportsVision: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
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
