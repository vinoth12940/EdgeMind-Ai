import Foundation

enum MockCatalogData {

    // MARK: - Download URLs (verified HuggingFace GGUF links)

    // Google DeepMind - Gemma
    static let gemma3n_e2b_URL = URL(string: "https://huggingface.co/bartowski/google_gemma-3n-E2B-it-GGUF/resolve/main/google_gemma-3n-E2B-it-Q4_K_M.gguf?download=true")
    static let gemma3n_e4b_URL = URL(string: "https://huggingface.co/bartowski/google_gemma-3n-E4B-it-GGUF/resolve/main/google_gemma-3n-E4B-it-Q4_K_M.gguf?download=true")
    static let gemma3_1b_URL = URL(string: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf?download=true")
    static let gemma3_4b_URL = URL(string: "https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf?download=true")
    static let gemma2_2b_URL = URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf?download=true")

    // Meta - Llama
    static let llama32_1b_URL = URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true")
    static let llama32_3b_URL = URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf?download=true")
    static let llama31_8b_URL = URL(string: "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf?download=true")

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

    // Microsoft - Phi
    static let phi4_mini_URL = URL(string: "https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf?download=true")
    static let phi35_mini_URL = URL(string: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf?download=true")
    static let phi3_mini_URL = URL(string: "https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf?download=true")

    // Mistral
    static let mistral7b_URL = URL(string: "https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf?download=true")
    static let ministral3b_URL = URL(string: "https://huggingface.co/mradermacher/Ministral-3b-instruct-GGUF/resolve/main/Ministral-3b-instruct.Q4_K_M.gguf?download=true")

    // DeepSeek
    static let deepseekR1_1_5b_URL = URL(string: "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf?download=true")
    static let deepseekR1_7b_URL = URL(string: "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf?download=true")

    // Hugging Face - SmolLM
    static let smolLM2_135m_URL = URL(string: "https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q8_0.gguf?download=true")
    static let smolLM2_360m_URL = URL(string: "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf?download=true")
    static let smolLM2_1_7b_URL = URL(string: "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf?download=true")

    // TinyLlama
    static let tinyLlama_URL = URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_0.gguf?download=true")

    // StabilityAI
    static let stableLM2_URL = URL(string: "https://huggingface.co/second-state/stablelm-2-zephyr-1.6b-GGUF/resolve/main/stablelm-2-zephyr-1_6b-Q4_K_M.gguf?download=true")

    // Apple - OpenELM
    static let openELM_1_1b_URL = URL(string: "https://huggingface.co/mradermacher/OpenELM-1_1B-Instruct-GGUF/resolve/main/OpenELM-1_1B-Instruct.Q4_K_M.gguf?download=true")
    static let openELM_3b_URL = URL(string: "https://huggingface.co/mradermacher/OpenELM-3B-Instruct-GGUF/resolve/main/OpenELM-3B-Instruct.Q4_K_M.gguf?download=true")

    // Liquid AI - LFM
    static let lfm_1_2b_URL = URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf?download=true")

    // MARK: - Full Model Catalog

    static let items: [ModelCatalogItem] = [

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // GOOGLE DEEPMIND
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Gemma 3n E2B",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Edge-optimized 2B effective parameter model. Designed specifically for mobile and on-device inference with efficient architecture.",
            parameterSize: "2B",
            diskSize: "1.6 GB",
            contextWindow: "32K",
            downloadURL: gemma3n_e2b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 3n E4B",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Larger edge-native model from Google with 4B effective parameters. Great balance of quality and speed for mobile.",
            parameterSize: "4B",
            diskSize: "3.0 GB",
            contextWindow: "32K",
            downloadURL: gemma3n_e4b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 3 1B Instruct",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Smallest Gemma 3 model. Ultra-fast chat for constrained devices with solid instruction following.",
            parameterSize: "1B",
            diskSize: "0.7 GB",
            contextWindow: "32K",
            downloadURL: gemma3_1b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 3 4B Instruct",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Mid-range Gemma 3 instruction model. Strong reasoning and instruction following at 4B scale.",
            parameterSize: "4B",
            diskSize: "2.5 GB",
            contextWindow: "128K",
            downloadURL: gemma3_4b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Gemma 2 2B Instruct",
            family: .gemma,
            variant: "Q4_K_M",
            summary: "Previous generation compact model. Still highly capable for general chat and reasoning tasks.",
            parameterSize: "2B",
            diskSize: "1.5 GB",
            contextWindow: "8K",
            downloadURL: gemma2_2b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // META
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Llama 3.2 1B Instruct",
            family: .llama,
            variant: "Q4_K_M",
            summary: "Meta's smallest Llama model. Optimized for on-device deployment with strong multilingual support.",
            parameterSize: "1B",
            diskSize: "0.7 GB",
            contextWindow: "128K",
            downloadURL: llama32_1b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Llama 3.2 3B Instruct",
            family: .llama,
            variant: "Q4_K_M",
            summary: "Best balance of Llama quality and mobile performance. Strong tool-calling and instruction following.",
            parameterSize: "3B",
            diskSize: "1.9 GB",
            contextWindow: "128K",
            downloadURL: llama32_3b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Llama 3.1 8B Instruct",
            family: .llama,
            variant: "Q4_K_M",
            summary: "Full-size Llama for iPad and Pro devices. Excellent at complex reasoning, coding, and multi-turn chat.",
            parameterSize: "8B",
            diskSize: "4.7 GB",
            contextWindow: "128K",
            downloadURL: llama31_8b_URL,
            supportsReasoning: true,
            supportsToolCalling: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // ALIBABA CLOUD (QWEN)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Qwen 3 0.6B",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Tiny thinking model with hybrid reasoning. Toggle between fast mode and deep-think mode on demand.",
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
            summary: "Balanced thinking model. Hybrid think/non-think modes with strong multilingual support across 100+ languages.",
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
            summary: "Sweet spot thinking model for mobile. Outperforms many larger models on reasoning benchmarks.",
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
            summary: "Powerful thinking model with tool calling. Best Qwen for complex tasks requiring step-by-step reasoning.",
            parameterSize: "8B",
            diskSize: "5.0 GB",
            contextWindow: "32K",
            downloadURL: qwen3_8b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true
        ),
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
            summary: "Versatile small model with massive 128K context window. Great for processing long documents on-device.",
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
            summary: "Mid-range instruct model with excellent coding and math capabilities. Large context window.",
            parameterSize: "3B",
            diskSize: "1.8 GB",
            contextWindow: "128K",
            downloadURL: qwen25_3b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 7B Instruct",
            family: .qwen,
            variant: "Q4_K_M",
            summary: "Flagship instruct model for iPad/Pro. Top tier reasoning and multilingual with massive context.",
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
        // MICROSOFT
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Phi-4 Mini 3.8B",
            family: .phi,
            variant: "Q4_K_M",
            summary: "Latest Microsoft small model. Excels at STEM, coding, and structured reasoning with tool-calling support.",
            parameterSize: "3.8B",
            diskSize: "2.4 GB",
            contextWindow: "128K",
            downloadURL: phi4_mini_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Phi-3.5 Mini 3.8B",
            family: .phi,
            variant: "Q4_K_M",
            summary: "Strong multilingual reasoning model from Microsoft. Excellent at math and logic tasks.",
            parameterSize: "3.8B",
            diskSize: "2.3 GB",
            contextWindow: "128K",
            downloadURL: phi35_mini_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Phi-3 Mini 3.8B",
            family: .phi,
            variant: "Q4_K_M",
            summary: "Foundational Phi model. Proven track record for on-device chat with balanced quality and speed.",
            parameterSize: "3.8B",
            diskSize: "2.2 GB",
            contextWindow: "4K",
            downloadURL: phi3_mini_URL,
            supportsReasoning: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MISTRAL AI
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "Ministral 3B Instruct",
            family: .mistral,
            variant: "Q4_K_M",
            summary: "Mistral's edge-optimized model. Strong performance at 3B with efficient tokenizer and fast inference.",
            parameterSize: "3B",
            diskSize: "1.9 GB",
            contextWindow: "128K",
            downloadURL: ministral3b_URL,
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Mistral 7B Instruct v0.3",
            family: .mistral,
            variant: "Q4_K_M",
            summary: "Classic open-weight model that started the efficiency revolution. Strong general purpose with function calling.",
            parameterSize: "7B",
            diskSize: "4.1 GB",
            contextWindow: "32K",
            downloadURL: mistral7b_URL,
            supportsReasoning: true,
            supportsToolCalling: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // DEEPSEEK
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "DeepSeek R1 Distill 1.5B",
            family: .deepSeek,
            variant: "Q4_K_M",
            summary: "Distilled reasoning model from DeepSeek-R1. Chain-of-thought on mobile with surprisingly strong math.",
            parameterSize: "1.5B",
            diskSize: "1.1 GB",
            contextWindow: "128K",
            downloadURL: deepseekR1_1_5b_URL,
            supportsReasoning: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "DeepSeek R1 Distill 7B",
            family: .deepSeek,
            variant: "Q4_K_M",
            summary: "Full-power distilled reasoning. Visible chain-of-thought with near-frontier math and code performance.",
            parameterSize: "7B",
            diskSize: "4.7 GB",
            contextWindow: "128K",
            downloadURL: deepseekR1_7b_URL,
            supportsReasoning: true,
            isThinkingModel: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // HUGGING FACE
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "SmolLM2 135M",
            family: .smolLM,
            variant: "Q8_0",
            summary: "Ultra-tiny model for instant responses. Great for testing pipelines or extremely constrained environments.",
            parameterSize: "135M",
            quantization: "GGUF Q8_0",
            diskSize: "145 MB",
            contextWindow: "8K",
            downloadURL: smolLM2_135m_URL,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "SmolLM2 360M",
            family: .smolLM,
            variant: "Q4_K_M",
            summary: "Tiny but surprisingly capable for its size. Good for simple classification and short-form generation.",
            parameterSize: "360M",
            diskSize: "220 MB",
            contextWindow: "8K",
            downloadURL: smolLM2_360m_URL,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "SmolLM2 1.7B Instruct",
            family: .smolLM,
            variant: "Q4_K_M",
            summary: "Compact instruct model tuned for fast on-device chat and short-form generation.",
            parameterSize: "1.7B",
            diskSize: "1.0 GB",
            contextWindow: "8K",
            downloadURL: smolLM2_1_7b_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STABILITY AI
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "StableLM 2 Zephyr 1.6B",
            family: .stableLM,
            variant: "Q4_K_M",
            summary: "Compact chat-tuned model from Stability AI. Optimized for conversational quality at small size.",
            parameterSize: "1.6B",
            diskSize: "1.0 GB",
            contextWindow: "4K",
            downloadURL: stableLM2_URL,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // APPLE
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "OpenELM 1.1B",
            family: .openELM,
            variant: "Q4_K_M",
            summary: "Apple's open-source language model. Layer-wise scaling for efficient parameter usage.",
            parameterSize: "1.1B",
            diskSize: "0.7 GB",
            contextWindow: "2K",
            downloadURL: openELM_1_1b_URL,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "OpenELM 3B",
            family: .openELM,
            variant: "Q4_K_M",
            summary: "Larger Apple model with improved reasoning. Designed with Apple Silicon efficiency in mind.",
            parameterSize: "3B",
            diskSize: "1.8 GB",
            contextWindow: "2K",
            downloadURL: openELM_3b_URL,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // TINYLLAMA (StatNLP)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "TinyLlama 1.1B OpenOrca",
            family: .tinyLlama,
            variant: "Q4_0",
            summary: "Very small Llama-architecture model for fastest first-run inference. Great for quick testing.",
            parameterSize: "1.1B",
            quantization: "GGUF Q4_0",
            diskSize: "607 MB",
            contextWindow: "2K",
            downloadURL: tinyLlama_URL,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // LIQUID AI
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ModelCatalogItem(
            displayName: "LFM2.5 1.2B Instruct",
            family: .lfm,
            variant: "Q4_K_M",
            summary: "Liquid Foundation Model 2.5 — state-space architecture for ultra-fast inference on edge devices.",
            parameterSize: "1.2B",
            diskSize: "0.7 GB",
            contextWindow: "32K",
            downloadURL: lfm_1_2b_URL,
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
            displayName: "Gemma 3 4B (MLX)",
            family: .gemma,
            variant: "4-bit MLX",
            summary: "Google Gemma 3 4B multimodal model on Apple Silicon. Supports vision — attach images to ask questions about them.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~2.5 GB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/gemma-3-4b-it-qat-4bit",
            supportsVision: true,
            supportsReasoning: true
        ),

        // META — MLX
        ModelCatalogItem(
            displayName: "Llama 3.2 1B (MLX)",
            family: .llama,
            variant: "4-bit MLX",
            summary: "Meta Llama 3.2 1B for Apple Silicon. Fast and efficient for everyday chat and reasoning.",
            parameterSize: "1B",
            quantization: "MLX 4-bit",
            diskSize: "~750 MB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Llama 3.2 3B (MLX)",
            family: .llama,
            variant: "4-bit MLX",
            summary: "Meta Llama 3.2 3B optimized for Apple Silicon. Strong multilingual support and reasoning.",
            parameterSize: "3B",
            quantization: "MLX 4-bit",
            diskSize: "~2 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),

        // ALIBABA CLOUD — MLX
        ModelCatalogItem(
            displayName: "Qwen 3 4B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Alibaba Qwen 3 4B with thinking mode on Apple Silicon. Toggle between fast and deep-think reasoning.",
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
            summary: "Alibaba Qwen 3 8B for Apple Silicon. Top-tier quality with thinking and tool-calling capabilities.",
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

        // MICROSOFT — MLX
        ModelCatalogItem(
            displayName: "Phi-4 Mini (MLX)",
            family: .phi,
            variant: "4-bit MLX",
            summary: "Microsoft Phi-4 Mini on Apple Silicon. Strong reasoning in a compact size.",
            parameterSize: "3.8B",
            quantization: "MLX 4-bit",
            diskSize: "~2.4 GB",
            contextWindow: "16K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/phi-4-mini-instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),

        // MISTRAL AI — MLX
        ModelCatalogItem(
            displayName: "Mistral 7B v0.3 (MLX)",
            family: .mistral,
            variant: "4-bit MLX",
            summary: "Mistral 7B v0.3 optimized for Apple Silicon. Excellent for general tasks.",
            parameterSize: "7B",
            quantization: "MLX 4-bit",
            diskSize: "~4.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            supportsReasoning: true,
            supportsToolCalling: true
        ),

        // DEEPSEEK — MLX
        ModelCatalogItem(
            displayName: "DeepSeek R1 Distill 1.5B (MLX)",
            family: .deepSeek,
            variant: "4-bit MLX",
            summary: "DeepSeek R1–distilled reasoning model on Apple Silicon. Think step-by-step locally.",
            parameterSize: "1.5B",
            quantization: "MLX 4-bit",
            diskSize: "~1 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
            supportsReasoning: true,
            isThinkingModel: true,
            recommendedForIPhone: true
        ),

        // HUGGING FACE — MLX
        ModelCatalogItem(
            displayName: "SmolLM2 1.7B (MLX)",
            family: .smolLM,
            variant: "4-bit MLX",
            summary: "Hugging Face SmolLM2 on Apple Silicon. Ultra-efficient for quick chat tasks.",
            parameterSize: "1.7B",
            quantization: "MLX 4-bit",
            diskSize: "~1.1 GB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/SmolLM2-1.7B-Instruct",
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ALIBABA (QWEN 3) — MLX
        ModelCatalogItem(
            displayName: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Ultra-small Qwen 3 thinking model on Apple Silicon. Thinking + tool calling in under 500 MB.",
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
            summary: "Compact Qwen 3 thinking model on Apple Silicon. Strong reasoning with tool calling.",
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

        // ALIBABA (QWEN 2.5) — MLX
        ModelCatalogItem(
            displayName: "Qwen 2.5 3B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Mid-size Qwen 2.5 on Apple Silicon. Balanced reasoning and efficiency.",
            parameterSize: "3B",
            quantization: "MLX 4-bit",
            diskSize: "~2 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 7B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Larger Qwen 2.5 on Apple Silicon. Full tool calling and strong reasoning.",
            parameterSize: "7B",
            quantization: "MLX 4-bit",
            diskSize: "~4.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true
        ),

        // DEEPSEEK — MLX
        ModelCatalogItem(
            displayName: "DeepSeek R1 Distill 7B (MLX)",
            family: .deepSeek,
            variant: "4-bit MLX",
            summary: "Larger DeepSeek R1–distilled reasoning model on Apple Silicon. Deep chain-of-thought locally.",
            parameterSize: "7B",
            quantization: "MLX 4-bit",
            diskSize: "~4.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit",
            supportsReasoning: true,
            isThinkingModel: true
        ),

        // META — MLX
        ModelCatalogItem(
            displayName: "Llama 3.1 8B (MLX)",
            family: .llama,
            variant: "4-bit MLX",
            summary: "Meta Llama 3.1 8B on Apple Silicon. Strong general model with tool calling support.",
            parameterSize: "8B",
            quantization: "MLX 4-bit",
            diskSize: "~4.5 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            supportsReasoning: true,
            supportsToolCalling: true
        ),

        // MICROSOFT — MLX
        ModelCatalogItem(
            displayName: "Phi-3.5 Mini (MLX)",
            family: .phi,
            variant: "4-bit MLX",
            summary: "Microsoft Phi-3.5 Mini on Apple Silicon. Compact 3.8B reasoning model with 128K context.",
            parameterSize: "3.8B",
            quantization: "MLX 4-bit",
            diskSize: "~2.2 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Phi-3.5-mini-instruct-4bit",
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // VISION LANGUAGE MODELS (VLM) — MLX
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // ALIBABA — VLM
        ModelCatalogItem(
            displayName: "Qwen3 VL 4B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Qwen3 Vision-Language 4B on Apple Silicon. Understands images and text together — describe photos, read documents, analyze charts.",
            parameterSize: "4B",
            quantization: "MLX 4-bit",
            diskSize: "~3.1 GB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit",
            supportsVision: true,
            supportsReasoning: true,
            supportsToolCalling: true,
            isThinkingModel: true
        ),
        ModelCatalogItem(
            displayName: "Qwen 2.5 VL 3B (MLX)",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "Qwen 2.5 Vision-Language 3B on Apple Silicon. Compact multimodal model for image understanding and visual Q&A.",
            parameterSize: "3B",
            quantization: "MLX 4-bit",
            diskSize: "~3.1 GB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // MISTRAL — MLX
        ModelCatalogItem(
            displayName: "Ministral 3B (MLX)",
            family: .mistral,
            variant: "4-bit MLX",
            summary: "Mistral's edge-optimized 3B model on Apple Silicon. Fast inference with tool calling support.",
            parameterSize: "3B",
            quantization: "MLX 4-bit",
            diskSize: "~2.8 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/Ministral-3-3B-Instruct-2512-4bit",
            supportsReasoning: true,
            supportsToolCalling: true,
            recommendedForIPhone: true
        ),

        // LIQUID AI — VLM
        ModelCatalogItem(
            displayName: "LFM 2.5 VL 1.6B (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid Foundation Model 2.5 VL on Apple Silicon. Ultra-compact 1.6B vision model — understands images on edge devices.",
            parameterSize: "1.6B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2.5-VL-1.6B-4bit",
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),
        ModelCatalogItem(
            displayName: "LFM 2 VL 1.6B (MLX)",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "Liquid Foundation Model 2 VL on Apple Silicon. Compact multimodal model for image understanding on mobile.",
            parameterSize: "1.6B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/LFM2-VL-1.6B-4bit",
            supportsVision: true,
            supportsReasoning: true,
            recommendedForIPhone: true
        ),

        // HUGGING FACE — VLM
        ModelCatalogItem(
            displayName: "SmolVLM Instruct (MLX)",
            family: .smolVLM,
            variant: "4-bit MLX",
            summary: "HuggingFace SmolVLM on Apple Silicon. Tiny vision model based on Idefics3 — visual Q&A in under 1.5 GB.",
            parameterSize: "2B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "8K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/SmolVLM-Instruct-4bit",
            supportsVision: true,
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
