# Dispatch Log

## 2026-09-07T04:44:57Z

Stabilize EdgeMind AI on iOS across all device tiers (Compact 4GB, Standard 6GB, Pro 8GB, Ultra 12GB+), purge obsolete 2023/2024 legacy weights, add the latest September 2026 edge text and vision models, eliminate memory leaks/crashes, and elevate user experience with a quick model switcher and smart hardware recommendations.

Key Requirements:
R1. Device Tier Classification & Memory Crash Prevention:
- Accurately classify 3GB and 4GB devices (including iPhone 10, 11, 12 series, SE 2/3, standard iPads) into .compact tier with safe 2,048 context and disabled flash attention in DeviceTier.swift & DeviceCapabilityService.swift. Also cover iPhone 13, 14, 15, 16, 17 series in DeviceTierTests.
- Enforce strict mutual exclusion between inference runtimes in RuntimeMemoryCoordinator.swift (specifically ensuring LiteRTRuntime is fully unloaded when switching to MLX, and vice-versa).
- Real-time headroom check via AvailableMemoryGuard.swift (os_proc_available_memory()) guarding inference & vision prefill, preventing hard Jetsam terminations by displaying a graceful in-chat notice when physical memory is constrained.
- On app backgrounding (scenePhase == .background), idle runtime weights must be evicted to prevent iOS background Jetsam termination.

R2. 2026 Edge Model & Vision Modernization:
- Purge obsolete 2023/2024 legacy models: TinyLlama 1.1B Chat (MLX/GGUF), StableLM 2 Zephyr 1.6B (MLX/GGUF), and Gemma 3 270M Instruct (MLX).
- Feature and verify premier 2026 edge lineup:
  * Vision-Language Models (VLMs): Google Gemma 4 E2B (LiteRT-LM), SmolVLM2 (500M / 2.2B MLX), Qwen 3.5 VL (0.8B / 4B MLX), Liquid AI LFM 2.5 VL (1.6B MLX).
  * Edge Text & Reasoning Models: Qwen 3.5 (0.8B / 2B MLX & GGUF), Qwen 3 2507 Thinking (0.6B / 1.7B / 4B MLX & GGUF), Liquid AI LFM 2.5 (350M / 1.2B Thinking), IBM Granite 3.3 2B (MLX & GGUF), Mistral Ministral 3 3B (MLX & GGUF), DeepSeek R1 Distill Qwen 1.5B (MLX & GGUF), and Apple Intelligence Foundation Models.
- Ensure all catalog items have unique deterministic UUID v5 IDs, working download/load paths, and 100% synchronized profiles in RuntimeProfiles.json.

R3. Usability & Discovery Highlights:
- Add an interactive Quick Model Switcher menu in ChatView.swift top bar allowing users to switch between installed models on the fly.
- In ModelLibraryView.swift, display a "Best for your iPhone" dynamic match badge recommending optimal models for the user's specific detected hardware tier.
- Provide a dedicated "Vision & Camera Ready" filter/shelf in ModelLibraryView.swift highlighting models that accept image attachments.

Verification & Automated Tests:
- DeviceTierTests
- DeviceCapabilityTests
- CatalogConsistencyTests
- RuntimeProfileTests
- ModelCatalogItemTests
- Verify runtime switching and backgrounding memory release behavior.
