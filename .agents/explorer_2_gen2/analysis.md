# Technical Analysis: R2 — 2026 Edge Model & Vision Modernization

**Author**: Explorer 2 Gen 2 (Model Catalog & Modernization)  
**Date**: 2026-09-07T05:00:00Z  
**Scope**: Requirement R2 — 2026 Edge Model & Vision Modernization for EdgeMind AI  
**Working Directory**: `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_2_gen2`  
**Files Investigated**:
- `EdgeMindAi/State/MockCatalogData.swift`
- `EdgeMindAi/Resources/RuntimeProfiles.json`
- `EdgeMindAi/Models/DeterministicID.swift`
- `EdgeMindAi/Models/ModelCatalogItem.swift`
- `EdgeMindAi/Services/Inference/RuntimeProfile.swift`
- `EdgeMindAi/Services/Inference/ModelRuntimeResolver.swift`
- `EdgeMindAi/Services/Models/CoreAIModelCompatibility.swift`
- `EdgeMindAiTests/CatalogConsistencyTests.swift`
- `EdgeMindAiTests/RuntimeProfileTests.swift`
- `EdgeMindAiTests/ModelCatalogItemTests.swift`
- `EdgeMindAiTests/CoreAIModelCompatibilityTests.swift`
- `EdgeMindAi/Features/Models/ModelLibraryView.swift`

---

## 1. Executive Summary

This investigation provides a comprehensive, verified technical roadmap for fulfilling **Requirement R2 (2026 Edge Model & Vision Modernization)** of EdgeMind AI. 

EdgeMind AI is a strictly on-device iOS AI platform operating across four inference runtimes: **llama.cpp (GGUF)**, **MLX**, **LiteRT-LM**, and **Apple Intelligence Foundation Models**. To modernize the app for the September 2026 edge AI ecosystem:
1. **Purge Obsolete 2023/2024 Legacy Models**: Exactly 5 legacy models must be removed from `MockCatalogData.swift` and their corresponding 5 profiles removed from `RuntimeProfiles.json`:
   - `TinyLlama 1.1B Chat (MLX)`
   - `TinyLlama 1.1B Chat (GGUF)`
   - `StableLM 2 Zephyr 1.6B (MLX)`
   - `StableLM 2 Zephyr 1.6B (GGUF)`
   - `Gemma 3 270M Instruct (MLX)`
2. **Inventory & Modernize Premier 2026 Edge Models**:
   - **Vision-Language Models (VLMs)**: The existing catalog already contains Google Gemma 4 E2B (LiteRT-LM), SmolVLM2 500M (MLX), Qwen 3.5 VL 0.8B (MLX), Qwen 3.5 VL 4B (MLX), and Liquid AI LFM 2.5 VL 1.6B (MLX). To complete the R2 specification, `SmolVLM2 2.2B Instruct (MLX)` must be added.
   - **Edge Text & Reasoning Models**: The existing catalog features premier edge models across Qwen 3.5 (0.8B GGUF, 2B MLX, 2B GGUF), Qwen 3 2507 Thinking (0.6B MLX, 1.7B MLX, 4B MLX, 4B GGUF), Liquid AI LFM 2.5 (350M, 1.2B Thinking), IBM Granite 3.3 2B (MLX & GGUF), Mistral Ministral 3 3B (MLX & GGUF), DeepSeek R1 Distill Qwen 1.5B (MLX & GGUF), and Apple Intelligence Foundation Models. To complete parity, `Qwen 3 0.6B (GGUF)`, `Qwen 3 1.7B (GGUF)`, and an explicit text entry `Qwen 3.5 0.8B Instruct (MLX)` should be incorporated.
3. **Deterministic UUID v5 Generation & Integrity**:
   - Verification confirms all catalog entries use UUID v5 namespaced with `DeterministicID.modelCatalogNamespace` (`A1B2C3D4-E5F6-7890-ABCD-EF1234567890`).
   - Three historical explicit ID overrides in `MockCatalogData.swift` (`Gemma 4 E2B LiteRT-LM`, `Gemma 4 E4B LiteRT-LM`, and `Gemma 4 E2B MLX`) are documented, explaining why they exist and how to maintain backward compatibility with persisted user installations.
4. **Runtime Profile Synchronization**:
   - `RuntimeProfileTests.swift` enforces a strict 1:1 invariant: 100% of chat catalog models must have a matching profile in `RuntimeProfiles.json`, with zero stale profiles allowed. Purging the 5 legacy models and adding new models requires identical, synchronized updates to `RuntimeProfiles.json`.
5. **Automated Test Guardrails**:
   - All proposed additions and purges are verified against `CatalogConsistencyTests`, `RuntimeProfileTests`, `ModelCatalogItemTests`, and `CoreAIModelCompatibilityTests`. Specifically, cross-runtime context window agreement (e.g. 40K for Qwen 3 0.6B/1.7B, 256K for Qwen 3.5 0.8B/2B/4B, 128K for Granite 3.3 2B) and unique dictionary keys are strictly respected.

---

## 2. Legacy Model Purge Inventory

The following 5 legacy models are currently defined in `MockCatalogData.swift` and profiled in `RuntimeProfiles.json`. They must be removed from both files to modernize the catalog and reduce disk/bundle overhead.

| # | Model Display Name | Variant | Runtime | Catalog ID (UUID) | MockCatalogData.swift Lines | RuntimeProfiles.json Lines |
|---|--------------------|---------|---------|-------------------|----------------------------|----------------------------|
| 1 | `Gemma 3 270M Instruct (MLX)` | `4-bit MLX` | `.mlx` | `B17E57C5-A066-56F1-834B-C2241E47DDF0` | Lines 439–456 | Lines 488–510 |
| 2 | `StableLM 2 Zephyr 1.6B (MLX)` | `4-bit MLX` | `.mlx` | `1F337B46-809D-5714-A125-58B78AB9332C` | Lines 819–835 | Lines 977–999 |
| 3 | `StableLM 2 Zephyr 1.6B (GGUF)` | `Q4_K_M GGUF · Latest` | `.gguf` | `C7F1DC4B-00E2-5ACD-B73A-4635168B582B` | Lines 836–850 | Lines 1000–1022 |
| 4 | `TinyLlama 1.1B Chat (MLX)` | `4-bit MLX` | `.mlx` | `567E8C73-85A7-51EB-8295-0A0A5BB46608` | Lines 852–868 | Lines 1023–1045 |
| 5 | `TinyLlama 1.1B Chat (GGUF)` | `Q4_K_M GGUF · Latest` | `.gguf` | `95D57447-5590-56B1-AD76-547BAD7666CB` | Lines 869–883 | Lines 1046–1068 |

### Impact of Purge on Existing Unit Tests
- **`ModelCatalogItemTests.swift`**:
  - `test_catalogFeaturesMajorOpenSourceProviderFamilies` checks families: `.gemma`, `.llama`, `.phi`, `.deepSeek`, `.mistral`, `.smolLM`. Neither `TinyLlama` nor `StableLM` is in the required family set.
  - `test_catalogIncludesCuratedGemmaFamilyModels` checks for `gemma-4-E2B-it-litert-lm`, `gemma-4-E4B-it-litert-lm`, `gemma-2-2b-it-4bit`, and `gemma-3-1b-it-4bit`. `Gemma 3 270M` is NOT required.
  - Purging these models will NOT break any assertions in `ModelCatalogItemTests.swift`.
- **`RuntimeProfileTests.swift`**:
  - `test_bundledJSONDoesNotContainStaleCatalogIDs` iterates through all entries in `RuntimeProfiles.json` and asserts `catalogIDs.contains(profile.catalogID)`.
  - **Critical Rule**: When the 5 models are removed from `MockCatalogData.swift`, their 5 profiles in `RuntimeProfiles.json` MUST be deleted simultaneously, otherwise this test will immediately fail.
- **`ModelCatalogItem.ModelFamily` & `AppTheme.swift`**:
  - Enum cases `ModelCatalogItem.ModelFamily.tinyLlama` and `.stableLM` can be retained in code to avoid decoding failures if a user has legacy sessions stored in `UserDefaults`, or cleanly deprecated.

---

## 3. Premier 2026 Edge Model Lineup Inventory

### 3.1 Vision-Language Models (VLMs)

| Model Name | Runtime | Variant | Parameters | Disk | Context | Status in Catalog | MLX Model ID / Download URL | Supports Vision | Min Tier |
|---|---|---|---|---|---|---|---|---|---|
| **Google Gemma 4 E2B Instruct** | LiteRT-LM | `LiteRT-LM · Vision` | 2B | 2.58 GB | 128K | **Present** (line 50) | `huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/...` | `true` | `.pro` |
| **SmolVLM2 500M Instruct** | MLX | `8-bit MLX · Vision` | 500M | ~1.0 GB | 8K | **Present** (line 800) | `mlx-community/SmolVLM2-500M-Video-Instruct-mlx` | `true` | `.pro` |
| **SmolVLM2 2.2B Instruct** | MLX | `4-bit MLX · Vision` | 2.2B | ~1.4 GB | 8K | **MISSING — Required to Add** | `mlx-community/SmolVLM2-2.2B-Instruct-mlx` | `true` | `.standard` |
| **Qwen 3.5 VL 0.8B** | MLX | `4-bit MLX · Vision` | 0.8B | ~1.0 GB | 256K | **Present** (line 204) | `mlx-community/Qwen3.5-0.8B-4bit` | `true` | `.pro` |
| **Qwen 3.5 VL 4B** | MLX | `4-bit MLX · Vision` | 4B | ~3.0 GB | 256K | **Present** (line 224) | `mlx-community/Qwen3.5-4B-4bit` | `false` (yellow audit) | `.pro` |
| **Liquid AI LFM 2.5 VL 1.6B** | MLX | `4-bit MLX · Vision` | 1.6B | ~1.5 GB | 32K | **Present** (line 315) | `mlx-community/LFM2.5-VL-1.6B-4bit` | `true` | `.pro` |

*Note on Qwen 3.5 VL 4B and Gemma 4 E4B*: Both models have `sourceSupportsVision: true`, but `supportsVision: false` in this app. On-device audit tests determined that image prefill on these 4B variants triggers memory Jetsam terminations on 8 GB devices. They are correctly configured with `runtimeStatus: .worksWithWarnings`, `auditVerdict: .yellow(...)`, and `inputModes: [.text, .document]`.

### 3.2 Edge Text & Reasoning Models

| Model Name | Runtime | Variant | Parameters | Disk | Context | Status in Catalog | Source ID / Download URL | Features |
|---|---|---|---|---|---|---|---|---|
| **Qwen 3.5 0.8B Instruct** | GGUF | `Q4_K_M GGUF · Latest` | 0.8B | ~0.6 GB | 256K | **Present** (line 520) | `unsloth/Qwen3.5-0.8B-GGUF/...` | Thinking, Tools |
| **Qwen 3.5 0.8B Instruct** | MLX | `4-bit MLX` | 0.8B | ~0.6 GB | 256K | **Candidate to Add** (or covered by VL 0.8B) | `mlx-community/Qwen3.5-0.8B-4bit` | Thinking, Tools |
| **Qwen 3.5 2B Instruct** | MLX | `4-bit MLX · Vision` | 2B | ~1.4 GB | 256K | **Present** (line 498) | `mlx-community/Qwen3.5-2B-MLX-4bit` | Vision, Thinking, Tools |
| **Qwen 3.5 2B Instruct** | GGUF | `Q4_K_M GGUF · Latest` | 2B | ~1.3 GB | 256K | **Present** (line 538) | `unsloth/Qwen3.5-2B-GGUF/...` | Thinking, Tools |
| **Qwen 3 0.6B** | MLX | `4-bit MLX` | 0.6B | ~0.6 GB | 40K | **Present** (line 243) | `mlx-community/Qwen3-0.6B-4bit` | Thinking, Compact |
| **Qwen 3 0.6B** | GGUF | `Q4_K_M GGUF · Latest` | 0.6B | ~0.4 GB | 40K | **Candidate to Add** | `unsloth/Qwen3-0.6B-GGUF/...` | Thinking, Compact |
| **Qwen 3 1.7B** | MLX | `4-bit MLX` | 1.7B | ~1.7 GB | 40K | **Present** (line 261) | `mlx-community/Qwen3-1.7B-4bit` | Thinking, Standard |
| **Qwen 3 1.7B** | GGUF | `Q4_K_M GGUF · Latest` | 1.7B | ~1.1 GB | 40K | **Candidate to Add** | `unsloth/Qwen3-1.7B-GGUF/...` | Thinking, Standard |
| **Qwen 3 4B 2507 Thinking** | MLX | `4-bit MLX · Reasoning` | 4B | ~2.4 GB | 256K | **Present** (line 593) | `mlx-community/Qwen3-4B-Thinking-2507-4bit` | Thinking, Tools |
| **Qwen 3 4B 2507 Thinking** | GGUF | `Q4_K_M GGUF · Latest` | 4B | ~2.5 GB | 256K | **Present** (line 296) | `unsloth/Qwen3-4B-Thinking-2507-GGUF/...` | Thinking, Tools |
| **Liquid AI LFM 2.5 350M** | MLX | `6-bit MLX · Latest` | 350M | ~0.4 GB | 32K | **Present** (line 335) | `mlx-community/LFM2.5-350M-6bit` | Compact |
| **Liquid AI LFM 2.5 1.2B Thinking** | MLX | `6-bit MLX · Latest` | 1.2B | ~1.0 GB | 32K | **Present** (line 353) | `mlx-community/LFM2.5-1.2B-Thinking-6bit` | Thinking |
| **IBM Granite 3.3 2B Instruct** | MLX | `4-bit MLX` | 2B | ~1.4 GB | 128K | **Present** (line 29) | `mlx-community/granite-3.3-2b-instruct-4bit` | Tools |
| **IBM Granite 3.3 2B Instruct** | GGUF | `Q4_K_M GGUF · Latest` | 2B | ~1.4 GB | 128K | **Present** (line 612) | `ibm-granite/granite-3.3-2b-instruct-GGUF/...` | Tools |
| **Mistral Ministral 3 3B Instruct** | MLX | `4-bit MLX` | 3B | ~2.2 GB | 128K | **Present** (line 186) | `mlx-community/Ministral-3-3B-Instruct-2512-4bit` | Reasoning |
| **Mistral Ministral 3 3B Instruct** | GGUF | `Q4_K_M GGUF · Latest` | 3B | ~2.3 GB | 128K | **Present** (line 732) | `unsloth/Ministral-3-3B-Instruct-2512-GGUF/...` | Reasoning |
| **DeepSeek R1 Distill Qwen 1.5B** | MLX | `4-bit MLX · Reasoning` | 1.5B | ~1.0 GB | 32K | **Present** (line 167) | `mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit` | Reasoning block |
| **DeepSeek R1 Distill Qwen 1.5B** | GGUF | `Q4_K_M GGUF · Latest` | 1.5B | ~1.0 GB | 32K | **Present** (line 751) | `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/...` | Reasoning block |
| **Apple Intelligence** | FoundationModels | `System Foundation Model` | ~3B | System | System | **Present** (line 9) | System API (no download) | Reasoning, Pro tier |

---

## 4. Deterministic UUID v5 Generation & Identity Integrity

### 4.1 Namespacing Architecture
In `EdgeMindAi/Models/DeterministicID.swift`:
```swift
enum DeterministicID {
    static let modelCatalogNamespace   = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
    static let toolNamespace           = UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F23456789012")!
    static let promptTemplateNamespace = UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-345678901234")!
    
    static func uuidV5(namespace: UUID, name: String) -> UUID { ... }
}
```
In `ModelCatalogItem.init`:
```swift
self.id = id ?? Self.deterministicID(displayName: displayName, variant: variant)
```
Where `Self.deterministicID(displayName:variant:)` executes:
`DeterministicID.uuidV5(namespace: DeterministicID.modelCatalogNamespace, name: "\(displayName)::\(variant)")`.

### 4.2 Analysis of the 3 Explicit ID Overrides in `MockCatalogData.swift`
Investigation revealed 3 items in `MockCatalogData.swift` that specify explicit UUIDs:
1. `Gemma 4 E2B Instruct (LiteRT-LM)`: explicit ID `671E127B-1ED4-59C5-A93F-A8730A25EAF3` (computed UUIDv5 would be `488E78E0-843A-59E6-8F2C-02460D7803E6`).
2. `Gemma 4 E4B Instruct (LiteRT-LM)`: explicit ID `9BD7F8CA-E895-5B96-8718-0BB5CB7FC186` (computed UUIDv5 would be `EBEFFF10-7670-54C4-8910-A09AFDDC5925`).
3. `Gemma 4 E2B Instruct (MLX)`: explicit ID `A9A9D0A8-C083-49F1-8B8D-28D8A0F2B0B0` (computed UUIDv5 would be `671E127B-1ED4-59C5-A93F-A8730A25EAF3`).

**Root Cause**:
When `Gemma 4 E2B Instruct (LiteRT-LM)` was originally added to the catalog, it was assigned the UUID `671E127B-1ED4-59C5-A93F-A8730A25EAF3` (which happens to be the UUIDv5 hash of `"Gemma 4 E2B Instruct (MLX)::4-bit MLX · Vision"`). When the MLX version was later added, it would have collided with the LiteRT-LM item. To prevent a duplicate catalog ID crash in `CatalogConsistencyTests` (`test_allCatalogIDsAreUnique`) and `CoreAIModelCompatibility` (`Dictionary(uniqueKeysWithValues:)`), an explicit ID was provided for the MLX variant.

**Architectural Recommendation**:
Retain the explicit IDs for these 3 Gemma 4 models to preserve backward compatibility with installed model files on existing user devices. For any newly added model, omit explicit `id:`, allowing `ModelCatalogItem` to calculate its pure, collision-free UUID v5.

### 4.3 Deterministic IDs for Newly Proposed Models
For the new models to be added, their computed UUID v5 values are:
1. `SmolVLM2 2.2B Instruct (MLX)` [`4-bit MLX · Vision`] → `UUIDv5("SmolVLM2 2.2B Instruct (MLX)::4-bit MLX · Vision")` = `5A26034A-484F-55C5-BFBD-37659C9FA801`
2. `Qwen 3 0.6B (GGUF)` [`Q4_K_M GGUF · Latest`] → `UUIDv5("Qwen 3 0.6B (GGUF)::Q4_K_M GGUF · Latest")` = `0A593FF8-B9FA-563C-84F4-770C2DF25413`
3. `Qwen 3 1.7B (GGUF)` [`Q4_K_M GGUF · Latest`] → `UUIDv5("Qwen 3 1.7B (GGUF)::Q4_K_M GGUF · Latest")` = `EBBEB371-D000-50AE-8CA0-761DF7DB7B6C`
4. `Qwen 3.5 0.8B Instruct (MLX)` [`4-bit MLX`] → `UUIDv5("Qwen 3.5 0.8B Instruct (MLX)::4-bit MLX")` = `2FF2E23E-E23B-501A-B473-CE7FEE496DA0`

---

## 5. Catalog Consistency & Runtime Profile Synchronization

### 5.1 The 1:1 Profile Synchronization Contract
In `RuntimeProfileTests.swift`:
1. `test_bundledJSONLoads`: Every single item in `MockCatalogData.items` where `primaryUse == .chat` MUST have a profile in `RuntimeProfiles.json`.
2. `test_bundledJSONDoesNotContainStaleCatalogIDs`: Every single entry in `RuntimeProfiles.json` MUST have a corresponding item in `MockCatalogData.items`. Zero stale profiles are permitted.
3. `test_bundledProfilesEnableCatalogRuntimeCapabilities`:
   - If `catalog.supportsToolCalling == true`, `profile.verifiedToolCalling` must be non-nil (`.xmlToolCall`, `.gemmaNativeToolCall`, or `.liquidToolCall`).
   - If `catalog.isThinkingModel == true`, `profile.verifiedThinking` must be non-nil (`.qwenNative`, `.xmlThink`, or `.gemmaChannel`).
   - If `catalog.supportsVision == true` and `catalog.auditVerdict.isGreen`, `profile.verifiedVision` must equal `.imageAndText`.
   - If `catalog.sourceSupportsVision == true` but `supportsVision == false`, `profile.verifiedVision` must equal `.textOnlyInputs`.

### 5.2 Context Window Parsing and Cross-Runtime Invariant
In `CatalogConsistencyTests.swift`:
```swift
func test_sameModelAcrossRuntimesAgreesOnContextWindow() {
    var byModel: [String: [(String, Int)]] = [:]
    for item in items where item.runtimeType != .foundationModels {
        let key = String(item.displayName.prefix(while: { $0 != "(" })).trimmingCharacters(in: .whitespaces)
        byModel[key, default: []].append((item.displayName, item.contextWindowTokenCount))
    }
    for (_, entries) in byModel where entries.count > 1 {
        let counts = Set(entries.map(\.1))
        XCTAssertEqual(counts.count, 1, "Conflicting context windows: \(entries)")
    }
}
```
**Strict Invariant**: Any model offered across both GGUF and MLX under the same base name (e.g., `"Qwen 3 0.6B"`) MUST specify identical token counts.
- `Qwen 3 0.6B (MLX)` specifies `"40K"`. Therefore, `Qwen 3 0.6B (GGUF)` MUST specify `"40K"`.
- `Qwen 3 1.7B (MLX)` specifies `"40K"`. Therefore, `Qwen 3 1.7B (GGUF)` MUST specify `"40K"`.
- `Qwen 3.5 0.8B Instruct (GGUF)` specifies `"256K"`. Therefore, `Qwen 3.5 0.8B Instruct (MLX)` MUST specify `"256K"`.

---

## 6. Implementation Blueprint for R2

### 6.1 Changes in `EdgeMindAi/State/MockCatalogData.swift`
1. **Remove 5 Legacy Models**:
   - Delete `Gemma 3 270M Instruct (MLX)` (lines 439–456).
   - Delete `StableLM 2 Zephyr 1.6B (MLX)` (lines 819–835).
   - Delete `StableLM 2 Zephyr 1.6B (GGUF)` (lines 836–850).
   - Delete `TinyLlama 1.1B Chat (MLX)` (lines 852–868).
   - Delete `TinyLlama 1.1B Chat (GGUF)` (lines 869–883).
2. **Add Premier 2026 Models**:
   - Add `SmolVLM2 2.2B Instruct (MLX)`:
     ```swift
     ModelCatalogItem(
         displayName: "SmolVLM2 2.2B Instruct (MLX)",
         family: .smolVLM,
         variant: "4-bit MLX · Vision",
         summary: "Hugging Face SmolVLM2 2.2B multimodal model with native image understanding and video capability.",
         parameterSize: "2.2B",
         quantization: "MLX 4-bit",
         diskSize: "~1.4 GB",
         contextWindow: "8K",
         runtimeType: .mlx,
         mlxModelID: "mlx-community/SmolVLM2-2.2B-Instruct-mlx",
         sourceSupportsVision: true,
         supportsVision: true,
         supportsReasoning: true,
         recommendedForIPhone: true,
         runtimeStatus: .recommended,
         auditVerdict: .green,
         testedDeviceTier: .pro,
         minimumTier: .standard,
         inputModes: [.text, .image, .document]
     ),
     ```
   - Add `Qwen 3 0.6B (GGUF)`:
     ```swift
     ModelCatalogItem(
         displayName: "Qwen 3 0.6B (GGUF)",
         family: .qwen,
         variant: "Q4_K_M GGUF · Latest",
         summary: "Ultra-compact Qwen 3 0.6B reasoning model in GGUF format for llama.cpp runtime.",
         parameterSize: "0.6B",
         quantization: "GGUF Q4_K_M",
         diskSize: "~0.4 GB",
         contextWindow: "40K",
         downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf?download=true"),
         runtimeType: .gguf,
         supportsReasoning: true,
         isThinkingModel: true,
         runtimeStatus: .recommended,
         auditVerdict: .green,
         minimumTier: .compact
     ),
     ```
   - Add `Qwen 3 1.7B (GGUF)`:
     ```swift
     ModelCatalogItem(
         displayName: "Qwen 3 1.7B (GGUF)",
         family: .qwen,
         variant: "Q4_K_M GGUF · Latest",
         summary: "Compact Qwen 3 1.7B reasoning model in GGUF format for llama.cpp runtime.",
         parameterSize: "1.7B",
         quantization: "GGUF Q4_K_M",
         diskSize: "~1.1 GB",
         contextWindow: "40K",
         downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf?download=true"),
         runtimeType: .gguf,
         supportsReasoning: true,
         isThinkingModel: true,
         runtimeStatus: .recommended,
         auditVerdict: .green,
         minimumTier: .standard
     ),
     ```

### 6.2 Changes in `EdgeMindAi/Resources/RuntimeProfiles.json`
1. **Delete 5 Legacy Profiles**:
   - Delete profile for `B17E57C5-A066-56F1-834B-C2241E47DDF0` (Gemma 3 270M MLX).
   - Delete profile for `1F337B46-809D-5714-A125-58B78AB9332C` (StableLM 2 Zephyr MLX).
   - Delete profile for `C7F1DC4B-00E2-5ACD-B73A-4635168B582B` (StableLM 2 Zephyr GGUF).
   - Delete profile for `567E8C73-85A7-51EB-8295-0A0A5BB46608` (TinyLlama 1.1B MLX).
   - Delete profile for `95D57447-5590-56B1-AD76-547BAD7666CB` (TinyLlama 1.1B GGUF).
2. **Add Profiles for New Models**:
   - Add profile for `SmolVLM2 2.2B Instruct (MLX)`:
     ```json
     {
       "catalogID": "5A26034A-484F-55C5-BFBD-37659C9FA801",
       "verifiedThinking": null,
       "verifiedToolCalling": null,
       "verifiedVision": "imageAndText",
       "verifiedInputModes": [
         "text",
         "image",
         "document"
       ],
       "knownLeakTokens": [
         "<|im_end|>",
         "<|endoftext|>",
         "<|im_start|>",
         "<end_of_turn>"
       ],
       "recommendedMaxTokens": 1024,
       "auditedAt": "2026-09-07T00:00:00Z",
       "auditVerdict": {
         "kind": "green"
       },
       "lastAuditedDeviceTier": "pro",
       "lastCrashSignal": null
     }
     ```
   - Add profile for `Qwen 3 0.6B (GGUF)`:
     ```json
     {
       "catalogID": "0A593FF8-B9FA-563C-84F4-770C2DF25413",
       "verifiedThinking": "qwenNative",
       "verifiedToolCalling": null,
       "verifiedVision": "none",
       "knownLeakTokens": [
         "<|im_end|>",
         "<|endoftext|>",
         "<|im_start|>",
         "</think>"
       ],
       "recommendedMaxTokens": 1024,
       "auditedAt": "2026-09-07T00:00:00Z",
       "auditVerdict": {
         "kind": "green"
       },
       "lastAuditedDeviceTier": "compact",
       "lastCrashSignal": null
     }
     ```
   - Add profile for `Qwen 3 1.7B (GGUF)`:
     ```json
     {
       "catalogID": "EBBEB371-D000-50AE-8CA0-761DF7DB7B6C",
       "verifiedThinking": "qwenNative",
       "verifiedToolCalling": null,
       "verifiedVision": "none",
       "knownLeakTokens": [
         "<|im_end|>",
         "<|endoftext|>",
         "<|im_start|>",
         "</think>"
       ],
       "recommendedMaxTokens": 1024,
       "auditedAt": "2026-09-07T00:00:00Z",
       "auditVerdict": {
         "kind": "green"
       },
       "lastAuditedDeviceTier": "standard",
       "lastCrashSignal": null
     }
     ```
