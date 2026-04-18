import Foundation

enum MockCatalogData {

    // MARK: - Model Catalog
    // Curated runnable set: Gemma 4 (GGUF) + Qwen 3 / Qwen 3 2507 + LFM 2.5 (MLX).
    // Capability flags reflect source vs runtime behavior in this app.
    // Capability flags reflect actual model card specs.

    static let items: [ModelCatalogItem] = [

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
            supportsToolCalling: true,
            recommendedForIPhone: true
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
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // ALIBABA CLOUD — Qwen 3 MLX
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
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
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
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
            recommendedForIPhone: true
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
            recommendedForIPhone: true
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
            recommendedForIPhone: true
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
            isThinkingModel: true
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
            recommendedForIPhone: true
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
            recommendedForIPhone: true
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
