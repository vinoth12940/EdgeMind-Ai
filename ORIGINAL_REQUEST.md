# Original User Request

## 2026-09-07T04:44:24Z

Stabilize EdgeMind AI on iOS across all device tiers (Compact 4GB, Standard 6GB, Pro 8GB, Ultra 12GB+), purge obsolete 2023/2024 legacy weights, add the latest September 2026 edge text and vision models, eliminate memory leaks/crashes, and elevate user experience with a quick model switcher and smart hardware recommendations.

Working directory: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai
Integrity mode: development

## Requirements

### R1. Device Tier Classification & Memory Crash Prevention
The app must reliably run without memory crashes across all supported iOS devices.
- Hardware detection in `DeviceTier.swift` and `DeviceCapabilityService.swift` must accurately classify 3 GB and 4 GB devices (including iPhone 10, 11, 12 series, SE 2/3, and standard iPads) into the `.compact` tier, allocating a safe 2,048-token context and disabling unsupported flash attention.
- Mutual exclusion between inference runtimes in `RuntimeMemoryCoordinator.swift` must be strictly enforced (specifically ensuring `LiteRTRuntime` is fully unloaded when switching to `MLX`, and vice-versa).
- A real-time headroom check via `AvailableMemoryGuard.swift` (`os_proc_available_memory()`) must guard inference and vision prefill, preventing hard Jetsam terminations by displaying a graceful in-chat notice when physical memory is constrained.
- On app backgrounding (`scenePhase == .background`), idle runtime weights must be evicted to prevent iOS background Jetsam termination.

### R2. 2026 Edge Model & Vision Modernization
The model catalog in `MockCatalogData.swift` and `RuntimeProfiles.json` must be modernized to the September 2026 ecosystem.
- Purge obsolete 2023/2024 legacy models: `TinyLlama 1.1B Chat` (MLX/GGUF), `StableLM 2 Zephyr 1.6B` (MLX/GGUF), and `Gemma 3 270M Instruct` (MLX).
- Feature and verify the premier 2026 edge lineup:
  - **Vision-Language Models (VLMs)**: Google Gemma 4 E2B (LiteRT-LM), SmolVLM2 (500M / 2.2B MLX), Qwen 3.5 VL (0.8B / 4B MLX), Liquid AI LFM 2.5 VL (1.6B MLX).
  - **Edge Text & Reasoning Models**: Qwen 3.5 (0.8B / 2B MLX & GGUF), Qwen 3 2507 Thinking (0.6B / 1.7B / 4B MLX & GGUF), Liquid AI LFM 2.5 (350M / 1.2B Thinking), IBM Granite 3.3 2B (MLX & GGUF), Mistral Ministral 3 3B (MLX & GGUF), DeepSeek R1 Distill Qwen 1.5B (MLX & GGUF), and Apple Intelligence Foundation Models.
- Ensure all catalog items have unique deterministic UUID v5 IDs, working download/load paths, and 100% synchronized profiles in `RuntimeProfiles.json`.

### R3. Usability & Discovery Highlights
The user interface must surface models intelligently based on hardware capabilities and streamline daily usage.
- Add an interactive Quick Model Switcher menu in `ChatView.swift` top bar allowing users to switch between installed models on the fly.
- In `ModelLibraryView.swift`, display a "Best for your iPhone" dynamic match badge recommending optimal models for the user's specific detected hardware tier.
- Provide a dedicated "Vision & Camera Ready" filter/shelf in `ModelLibraryView.swift` highlighting models that accept image attachments.

## Acceptance Criteria

### Verification & Automated Tests
- [ ] `DeviceTierTests` passes with correct classification for all device families (including iPhone 10, 11, 12, 13, 14, 15, 16, 17 series).
- [ ] `DeviceCapabilityTests` passes with safe context size (2,048 tokens) and disabled flash attention for A11–A13 devices.
- [ ] `CatalogConsistencyTests` passes with 0 duplicate IDs, valid context windows, and correct input mode mappings.
- [ ] `RuntimeProfileTests` passes with 100% of chat models profiled in `RuntimeProfiles.json`.
- [ ] `ModelCatalogItemTests` passes with all featured family requirements intact.
- [ ] Switching between LiteRT vision models and MLX models releases all memory from the previous runtime.
- [ ] Minimizing the app releases idle inference memory without terminating.
- [ ] Quick Model Switcher menu functions directly from the Chat top bar.
