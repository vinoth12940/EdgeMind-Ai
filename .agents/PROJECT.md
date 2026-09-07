# Project: EdgeMind AI Stabilization & Modernization (September 2026)

## Architecture
- **Inference Runtimes**: GGUF (llama.cpp via LocalLlamaRuntime), MLX (via MLXRuntime), LiteRT-LM (via LiteRTRuntime), and Apple Foundation Models (via AppleFoundationModelService).
- **Coordination & Mutual Exclusion**: `RuntimeMemoryCoordinator` enforces mutual exclusion across runtimes so LiteRT and MLX never share physical memory concurrently. Evicts idle weights on backgrounding (`scenePhase == .background`).
- **Memory Protection**: `AvailableMemoryGuard` calls `os_proc_available_memory()` to compute real-time headroom for model weights + context KV cache + vision prefill buffer, issuing in-chat alerts before Jetsam SIGKILL.
- **Hardware Tiering**: `DeviceTier` and `DeviceCapabilityService` detect hardware model and RAM, classifying <= 4GB devices (iPhone 10, 11, 12, SE 2/3, 13 mini, standard iPads) into `.compact` with safe 2,048 context and flash attention disabled.
- **Model Catalog & Profiles**: `MockCatalogData.swift` and `RuntimeProfiles.json` maintain synchronized metadata, input modes, deterministic UUID v5 IDs, and verified capabilities.
- **UI & Discovery**: `ChatView.swift` top bar interactive Quick Model Switcher and `ModelLibraryView.swift` dynamic "Best for your iPhone" match badge and dedicated "Vision & Camera Ready" carousel shelf.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Compact Tier Classification | Classify 3GB & 4GB devices (iPhone 10/11/12/SE 2/3/13 mini, iPads) into `.compact` | M1 | ORIGINAL_REQUEST §R1 |
| 2 | Safe Context Allocation | Allocate safe 2,048 tokens for `.compact` tier devices across DeviceCapabilityService | M1 | ORIGINAL_REQUEST §R1 |
| 3 | Flash Attention Disabling | Disable flash attention on A10–A14 chips (iPhones & iPads) to prevent Metal shader crashes | M1 | ORIGINAL_REQUEST §R1 |
| 4 | Device Tiers 13–17 & Ultra | Add explicit static mappings for iPhone 13, 14, 15, 16, 17 series and Ultra tier (12GB+) | M1 | ORIGINAL_REQUEST §R1 |
| 5 | Runtime Mutual Exclusion | Strictly enforce unloading of LiteRT when switching to MLX and vice versa in RuntimeMemoryCoordinator | M1 | ORIGINAL_REQUEST §R1 |
| 6 | Real-Time Headroom Guard | Real-time `os_proc_available_memory()` check guarding inference & multi-turn vision prefill | M1 | ORIGINAL_REQUEST §R1 |
| 7 | App Background Eviction | Evict idle inference runtime weights in `EdgeMindAiApp.swift` on `scenePhase == .background` | M1 | ORIGINAL_REQUEST §R1 |
| 8 | Purge Legacy Models | Purge TinyLlama 1.1B (MLX/GGUF), StableLM 2 Zephyr 1.6B (MLX/GGUF), Gemma 3 270M (MLX) | M2 | ORIGINAL_REQUEST §R2 |
| 9 | Add 2026 Premier Models | Add SmolVLM2 2.2B (MLX), Qwen 3 0.6B (GGUF), Qwen 3 1.7B (GGUF), verify full 2026 lineup | M2 | ORIGINAL_REQUEST §R2 |
| 10 | Deterministic UUID v5 & URLs | Ensure all catalog items have valid UUID v5 IDs, working load paths, and context matching | M2 | ORIGINAL_REQUEST §R2 |
| 11 | Synchronize Runtime Profiles | Ensure 100% of chat models have valid, non-stale profiles in `RuntimeProfiles.json` | M2 | ORIGINAL_REQUEST §R2 |
| 12 | Quick Model Switcher Menu | Interactive model switcher in `ChatView.swift` top bar sourcing from `availableChatModels` | M3 | ORIGINAL_REQUEST §R3 |
| 13 | "Best for your iPhone" Badge | Dynamic match badge in `ModelLibraryView.swift` via `ModelCatalogItem.isBestMatch(for:)` | M3 | ORIGINAL_REQUEST §R3 |
| 14 | "Vision & Camera Ready" Shelf | Dedicated carousel shelf & updated filter bar in `ModelLibraryView.swift` for VLMs | M3 | ORIGINAL_REQUEST §R3 |
| 15 | E2E Integration & Verification | All unit & integration test suites pass, xcodegen project sync, zero build errors | M4 | ORIGINAL_REQUEST §Acceptance |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: Hardware Tier Classification & Memory Crash Prevention | Features 1, 2, 3, 4, 5, 6, 7 (DeviceTier, DeviceCapabilityService, RuntimeMemoryCoordinator, AvailableMemoryGuard, EdgeMindAiApp, DeviceTierTests, DeviceCapabilityTests) | none | DONE |
| 2 | M2: 2026 Edge Model & Vision Modernization | Features 8, 9, 10, 11 (MockCatalogData, RuntimeProfiles.json, CatalogConsistencyTests, RuntimeProfileTests, ModelCatalogItemTests) | none | DONE |
| 3 | M3: Usability & Discovery Highlights | Features 12, 13, 14 (ChatView quick switcher, ModelLibraryView match badge and vision shelf, ModelCatalogItem.isBestMatch) | M1, M2 | DONE |
| 4 | M4: Final Integration & E2E Test Suite | Feature 15 (Full test suite execution, xcodegen project generation, verification of runtime switching & background eviction) | M1, M2, M3 | DONE |
| 5 | M5: Release & App Store Submission | v0.3.0 Build 6 archive, dSYM verification, App Store Connect upload, build attachment & review submission via API | M4 | DONE (WAITING_FOR_REVIEW) |

## Interface Contracts
### `DeviceTier` ↔ `DeviceCapabilityService`
- `DeviceCapabilityService.contextSize(for: machine)` returns `DeviceTier.classify(machine: machine).safeContextTokens` (2,048 for `.compact`, 4,096 for `.standard`, 8,192 for `.pro`, 16,384 for `.ultra`).
- `DeviceCapabilityService.supportsFlashAttention(for: machine)` returns `false` if `machine.hasPrefix("iPhone10,") || ... || machine.hasPrefix("iPhone13,") || machine.hasPrefix("iPad7,") || ... || machine.hasPrefix("iPad13,")`.

### `ModelCatalogItem` ↔ `ModelLibraryView`
- `ModelCatalogItem.isBestMatch(for tier: DeviceTier) -> Bool`:
  Returns true if `minimumTier <= tier`, `estimatedResidentGB(contextTokens: tier.safeContextTokens) <= tier.usableWeightGB`, `!auditVerdict.isRed`, and conforms to tier parameter size targets.

### `AppStateStore` ↔ `ChatView` Top Bar
- `store.availableChatModels`: Filters `installedModels` where `primaryUse == .chat && isReadyChatModel($0)`.
- Model selection button triggers `store.setDefaultModel(id: model.catalogItem.id)` and `RuntimeMemoryCoordinator.prepareForRuntime(model.catalogItem.runtimeType)`.

## Code Layout
- `EdgeMindAi/Services/Inference/DeviceTier.swift`
- `EdgeMindAi/Services/Inference/DeviceCapabilityService.swift`
- `EdgeMindAi/Services/Inference/RuntimeMemoryCoordinator.swift`
- `EdgeMindAi/Services/Inference/AvailableMemoryGuard.swift`
- `EdgeMindAi/App/EdgeMindAiApp.swift`
- `EdgeMindAi/State/MockCatalogData.swift`
- `EdgeMindAi/Resources/RuntimeProfiles.json`
- `EdgeMindAi/Models/ModelCatalogItem.swift`
- `EdgeMindAi/Features/Chat/ChatView.swift`
- `EdgeMindAi/Features/Models/ModelLibraryView.swift`
- `EdgeMindAiTests/DeviceTierTests.swift`
- `EdgeMindAiTests/DeviceCapabilityTests.swift`
- `EdgeMindAiTests/CatalogConsistencyTests.swift`
- `EdgeMindAiTests/RuntimeProfileTests.swift`
- `EdgeMindAiTests/ModelCatalogItemTests.swift`
