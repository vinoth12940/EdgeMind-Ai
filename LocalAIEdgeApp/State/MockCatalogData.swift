import Foundation

enum MockCatalogData {

    // MARK: - Download URLs (verified HuggingFace GGUF links)

    // Google DeepMind - Gemma
    static let gemma3n_e2b_URL = URL(string: "https://huggingface.co/bartowski/google_gemma-3n-E2B-it-GGUF/resolve/main/google_gemma-3n-E2B-it-Q4_K_M.gguf?download=true")
    static let gemma3n_e4b_URL = URL(string: "https://huggingface.co/bartowski/google_gemma-3n-E4B-it-GGUF/resolve/main/google_gemma-3n-E4B-it-Q4_K_M.gguf?download=true")
    static let gemma3_1b_URL = URL(string: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf?download=true")
    static let gemma3_4b_URL = URL(string: "https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf?download=true")
    static let gemma2_2b_URL = URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf?download=true")

    // Alibaba - Qwen
    static let qwen3_0_6b_URL = URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf?download=true")
    static let qwen3_1_7b_URL = URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf?download=true")
    static let qwen3_4b_URL = URL(string: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true")
    static let qwen3_8b_URL = URL(string: "https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true")
    static let qwen25_0_5b_URL = URL(string: "https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true")
    static let qwen25_1_5b_URL = URL(string: "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf?download=true")
    static let qwen25_3b_URL = URL(string: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf?download=true")
    static let qwen25_7b_URL = URL(string: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf?download=true")
    static let qwen25_coder_1_5b_URL = URL(string: "https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf?download=true")

    // Liquid AI - LFM
    static let lfm_1_2b_URL = URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf?download=true")
    static let lfm_vl_1_6b_URL = URL(string: "https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/LFM2.5-VL-1.6B-Q4_0.gguf?download=true")
    static let lfm_audio_1_5b_URL = URL(string: "https://huggingface.co/LiquidAI/LFM2.5-Audio-1.5B-GGUF/resolve/main/LFM2.5-Audio-1.5B-Q4_0.gguf?download=true")

    // MARK: - Full Model Catalog
    // V1 scope: Qwen, Gemma, LFM families + Kokoro voice asset.
    // Capability flags reflect actual model card specs (verified Mar 2026).
    // Vision: models with dedicated vision encoder in weights.
    // Tool Calling: models with native <tool_call> tokens in chat template.
    // Thinking: models with native /think + /no_think soft switches (Qwen 3).
    // Gemma tool calling is prompt-only (no dedicated template tokens) — not flagged.

    static let items: [ModelCatalogItem] = [

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // GOOGLE DEEPMIND — GGUF
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // Gemma 3n: MatFormer multimodal architecture — image + video + audio encoder baked in.
        ModelCatalogItem(
            displayName: "Gemma 3n E2B",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Edge-native 2B model from Google with multimodal architecture. Supports image, video, and audio input. Designed for mobile inference.",
            parameterSize: "2B",
            diskSize: "1.6 GB",
            contextWindow: "32K",
            downloadURL: gemma3n_e2b_URL,
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 3n E4B",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Edge-native 4B model from Google with multimodal architecture. Supports image, video, and audio input. Best quality/speed for mobile.",
            parameterSize: "4B",
            diskSize: "3.0 GB",
            contextWindow: "32K",
            downloadURL: gemma3n_e4b_URL,
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        // Gemma 3 1B: text-only (no vision encoder in this size).
        ModelCatalogItem(
            displayName: "Gemma 3 1B Instruct",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Smallest Gemma 3 model. Ultra-fast text chat for constrained devices with solid instruction following.",
            parameterSize: "1B",
            diskSize: "0.7 GB",
            contextWindow: "32K",
            downloadURL: gemma3_1b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        // Gemma 3 4B: vision via SigLIP encoder (896×896).
        ModelCatalogItem(
            displayName: "Gemma 3 4B Instruct",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Mid-range Gemma 3 with vision support via SigLIP encoder (896×896). Understands images and text together.",
            parameterSize: "4B",
            diskSize: "2.5 GB",
            contextWindow: "128K",
            downloadURL: gemma3_4b_URL,
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        // Gemma 2 2B: text-only, previous generation.
        ModelCatalogItem(
            displayName: "Gemma 2 2B Instruct",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Previous generation compact model. Highly capable for general chat and reasoning tasks.",
            parameterSize: "2B",
            diskSize: "1.5 GB",
            contextWindow: "8K",
            downloadURL: gemma2_2b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // ALIBABA CLOUD (QWEN) — GGUF
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // Qwen 3: all sizes have native <tool_call> tokens + /think /no_think switches.
        ModelCatalogItem(
            displayName: "Qwen 3 0.6B",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Tiny thinking model with native tool calling. Toggle between fast mode and deep-think mode on demand.",
            parameterSize: "0.6B",
            diskSize: "0.5 GB",
            contextWindow: "32K",
            downloadURL: qwen3_0_6b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 1.7B",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Balanced thinking model with native tool calling. Hybrid think/non-think modes, 100+ languages.",
            parameterSize: "1.7B",
            diskSize: "1.1 GB",
            contextWindow: "32K",
            downloadURL: qwen3_1_7b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 4B",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Sweet spot thinking model for mobile. Native tool calling, outperforms many larger models on reasoning benchmarks.",
            parameterSize: "4B",
            diskSize: "2.6 GB",
            contextWindow: "32K",
            downloadURL: qwen3_4b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 8B",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Powerful thinking model with deep reasoning and native tool calling. Requires iPhone 15 Pro Max or iPad Pro — ~5 GB, 8 GB RAM recommended.",
            parameterSize: "8B",
            diskSize: "5.0 GB",
            contextWindow: "32K",
            downloadURL: qwen3_8b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true
        ),
        // Qwen 2.5: tool calling reliable at 3B+, unreliable at 0.5B/1.5B.
        ModelCatalogItem(
            displayName: "Qwen 2.5 0.5B Instruct",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Ultra-lightweight instruct model. Fast enough for real-time completions on any device.",
            parameterSize: "0.5B",
            diskSize: "379 MB",
            contextWindow: "128K",
            downloadURL: qwen25_0_5b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 1.5B Instruct",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Versatile small model with massive 128K context window. Great for long documents on-device.",
            parameterSize: "1.5B",
            diskSize: "0.9 GB",
            contextWindow: "128K",
            downloadURL: qwen25_1_5b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 3B Instruct",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Mid-range instruct model with reliable tool calling, strong coding and math. Large context window.",
            parameterSize: "3B",
            diskSize: "1.8 GB",
            contextWindow: "128K",
            downloadURL: qwen25_3b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 7B Instruct",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Flagship instruct model with reliable tool calling. Best on iPhone 15 Pro Max or iPad Pro — ~4.4 GB, 8 GB RAM recommended.",
            parameterSize: "7B",
            diskSize: "4.4 GB",
            contextWindow: "128K",
            downloadURL: qwen25_7b_URL,
            supportsReasoning: true,
            supportsToolCalling: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 Coder 1.5B",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Specialized coding assistant. Code completion, generation, and debugging optimized for mobile devices.",
            parameterSize: "1.5B",
            diskSize: "0.9 GB",
            contextWindow: "128K",
            downloadURL: qwen25_coder_1_5b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // LIQUID AI — GGUF
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // LFM2.5: native <|tool_call_start|> tokens in chat template.
        ModelCatalogItem(
            displayName: "LFM2.5 1.2B Instruct",
            family: .lfm,
            variant: "Q4_K_M",
            summary: "Liquid Foundation Model 2.5 with native tool calling. State-space architecture for ultra-fast inference on edge devices.",
            parameterSize: "1.2B",
            diskSize: "0.7 GB",
            contextWindow: "32K",
            downloadURL: lfm_1_2b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 VL 1.6B",
            family: .lfm,
            variant: "Q4_0",
            summary: "Liquid vision-language model for multimodal chat on edge devices. Supports image + text understanding.",
            parameterSize: "1.6B",
            diskSize: "696 MB",
            contextWindow: "32K",
            downloadURL: lfm_vl_1_6b_URL,
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 Audio 1.5B",
            family: .lfm,
            variant: "Q4_0",
            summary: "Liquid native audio-language model for ASR, TTS, and speech-to-speech. Uses llama.cpp GGUF audio runners with paired projection and vocoder weights.",
            parameterSize: "1.5B",
            diskSize: "696 MB",
            contextWindow: "32K",
            downloadURL: lfm_audio_1_5b_URL,
            primaryUse: .voice,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MLX MODELS (Apple Silicon optimized)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // GOOGLE DEEPMIND — MLX
        ModelCatalogItem(
            displayName: "Gemma 3 1B (MLX)",
            family: .gemma,
            variant: "4-bit MLX",
            summary: "Google Gemma 3 1B quantized for Apple Silicon via MLX. Native Metal GPU acceleration for fast chat.",
            parameterSize: "1B",
            quantization: "MLX 4-bit",
            diskSize: "~800 MB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/gemma-3-1b-it-qat-4bit",
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 3n E2B (MLX)",
            family: .gemma,
            variant: "4-bit MLX",
            summary: "Gemma 3n E2B multimodal model for Apple Silicon with MLX acceleration. Supports image, video, and audio input.",
            parameterSize: "2B",
            quantization: "MLX 4-bit",
            diskSize: "~4.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/gemma-3n-E2B-it-4bit",
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 3n E4B (MLX)",
            family: .gemma,
            variant: "4-bit MLX",
            summary: "Gemma 3n E4B multimodal model for Apple Silicon with MLX acceleration. Supports image, video, and audio input.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~5.8 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/gemma-3n-E4B-it-4bit",
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 3 4B Instruct (MLX)",
            family: .gemma,
            variant: "4-bit MLX",
            summary: "Gemma 3 4B vision-language model on Apple Silicon with MLX acceleration for image + text tasks.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~3.0 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/gemma-3-4b-it-qat-4bit",
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 2 2B Instruct (MLX)",
            family: .gemma,
            variant: "4-bit MLX",
            summary: "Gemma 2 2B text model on Apple Silicon using MLX. Good general chat quality with efficient memory use.",
            parameterSize: "2B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/gemma-2-2b-it-4bit",
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // LIQUID AI — MLX
        ModelCatalogItem(
            displayName: "LFM2.5 1.2B Instruct (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid Foundation Model 2.5 quantized for Apple Silicon. Native MLX runtime for faster iPhone/iPad inference.",
            parameterSize: "1.2B",
            quantization: "MLX 4-bit",
            diskSize: "~0.8 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 VL 1.6B (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid vision-language model on Apple Silicon with MLX acceleration for image + text understanding.",
            parameterSize: "1.6B",
            quantization: "MLX 4-bit",
            diskSize: "~0.7 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-VL-1.6B-4bit",
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "LFM2.5 Audio 1.5B (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid native audio-language model on Apple Silicon via mlx-audio. Supports text/audio input and interleaved text+audio output.",
            parameterSize: "1.5B",
            quantization: "MLX 4-bit",
            diskSize: "~1.8 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-Audio-1.5B-4bit",
            primaryUse: .voice,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ALIBABA CLOUD — MLX
        // Qwen 3 MLX: all sizes have native <tool_call> tokens + /think /no_think switches.
        ModelCatalogItem(
            displayName: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Ultra-small Qwen 3 thinking model on Apple Silicon. Native tool calling, thinking mode under 500 MB.",
            parameterSize: "0.6B",
            quantization: "MLX 4-bit",
            diskSize: "~0.5 GB",
            contextWindow: "32K",
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
            summary: "Compact Qwen 3 thinking model on Apple Silicon. Native tool calling, strong reasoning in ~1.2 GB.",
            parameterSize: "1.7B",
            quantization: "MLX 4-bit",
            diskSize: "~1.2 GB",
            contextWindow: "32K",
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
            summary: "Qwen 3 4B with thinking mode and native tool calling on Apple Silicon. Toggle between fast and deep-think reasoning.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~2.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-4B-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 3 8B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Qwen 3 8B with thinking mode and native tool calling on Apple Silicon. Best on iPhone 15 Pro Max or iPad Pro — ~5 GB, 8 GB RAM recommended.",
            parameterSize: "8B",
            quantization: "MLX 4-bit",
            diskSize: "~5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen3-8B-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 0.5B Instruct (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Ultra-lightweight Qwen 2.5 model on Apple Silicon. Great for fast, low-memory mobile chat.",
            parameterSize: "0.5B",
            quantization: "MLX 4-bit",
            diskSize: "~278 MB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 1.5B Instruct (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Compact Qwen 2.5 model on Apple Silicon with large context support for long prompts and documents.",
            parameterSize: "1.5B",
            quantization: "MLX 4-bit",
            diskSize: "~869 MB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 Coder 1.5B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Alibaba code-specialized model on Apple Silicon. Perfect for coding assistance.",
            parameterSize: "1.5B",
            quantization: "MLX 4-bit",
            diskSize: "~1 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit",
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 3B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Mid-size Qwen 2.5 on Apple Silicon with reliable tool calling. Balanced reasoning and efficiency.",
            parameterSize: "3B",
            quantization: "MLX 4-bit",
            diskSize: "~2 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 7B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Larger Qwen 2.5 on Apple Silicon with reliable tool calling. Best on iPhone 15 Pro Max or iPad Pro — ~4.5 GB, 8 GB RAM recommended.",
            parameterSize: "7B",
            quantization: "MLX 4-bit",
            diskSize: "~4.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // VOICE ASSETS
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // Kokoro 82M: StyleTTS2-based TTS model — text in, audio out. Not an LLM.
        ModelCatalogItem(
            displayName: "Kokoro 82M Voice",
            family: .kokoro,
            variant: "4-bit MLX",
            summary: "Downloadable Kokoro voice asset for future native MLX speech synthesis. The current app uses Apple Speech for dictation and spoken replies while this asset path is prepared.",
            parameterSize: "82M",
            quantization: "MLX 4-bit",
            diskSize: "~340 MB",
            contextWindow: "Audio",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Kokoro-82M-4bit",
            primaryUse: .voice,
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
