# Handoff Report: R2 — 2026 Edge Model & Vision Modernization

**Author**: Explorer 2 Gen 2 (Model Catalog & Modernization)  
**Date**: 2026-09-07T05:05:00Z  
**Target Milestone**: R2 — 2026 Edge Model & Vision Modernization  
**Working Directory**: `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_2_gen2`  
**Associated Analysis**: `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_2_gen2/analysis.md`

---

## 1. Observation

### 1.1 Legacy Models in `EdgeMindAi/State/MockCatalogData.swift`
Direct inspection of `EdgeMindAi/State/MockCatalogData.swift` confirmed the exact locations of the 5 legacy models slated for deletion:
1. `Gemma 3 270M Instruct (MLX)`:
   - Lines 439–456:
     ```swift
     ModelCatalogItem(
         displayName: "Gemma 3 270M Instruct (MLX)",
         family: .gemma,
         variant: "4-bit MLX",
         summary: "Google Gemma 3 ultra-lightweight 270M instruct model. Perfect for fast on-device chat on standard devices.",
         parameterSize: "270M",
         quantization: "MLX 4-bit",
         diskSize: "~150 MB",
         contextWindow: "32K",
         runtimeType: .mlx,
         mlxModelID: "mlx-community/gemma-3-270m-it-4bit",
         supportsReasoning: true,
         recommendedForIPhone: true,
         runtimeStatus: .recommended,
         auditVerdict: .green,
         testedDeviceTier: .pro,
         minimumTier: .compact
     ),
     ```
2. `StableLM 2 Zephyr 1.6B (MLX)`:
   - Lines 819–835:
     ```swift
     ModelCatalogItem(
         displayName: "StableLM 2 Zephyr 1.6B (MLX)",
         family: .stableLM,
         variant: "4-bit MLX",
         summary: "Stability AI StableLM 2 1.6B Zephyr model converted to MLX. Highly responsive chat assistant.",
         parameterSize: "1.6B",
         quantization: "MLX 4-bit",
         diskSize: "~1.0 GB",
         contextWindow: "8K",
         runtimeType: .mlx,
         mlxModelID: "mlx-community/stablelm-2-zephyr-1_6b-4bit",
         recommendedForIPhone: true,
         runtimeStatus: .recommended,
         auditVerdict: .green,
         testedDeviceTier: .pro,
         minimumTier: .standard
     ),
     ```
3. `StableLM 2 Zephyr 1.6B (GGUF)`:
   - Lines 836–850:
     ```swift
     ModelCatalogItem(
         displayName: "StableLM 2 Zephyr 1.6B (GGUF)",
         family: .stableLM,
         variant: "Q4_K_M GGUF · Latest",
         summary: "Stability AI StableLM 2 1.6B Zephyr model in GGUF format.",
         parameterSize: "1.6B",
         quantization: "GGUF Q4_K_M",
         diskSize: "~1.0 GB",
         contextWindow: "8K",
         downloadURL: URL(string: "https://huggingface.co/second-state/stablelm-2-zephyr-1.6b-GGUF/resolve/main/stablelm-2-zephyr-1.6b-Q4_K_M.gguf?download=true"),
         runtimeType: .gguf,
         runtimeStatus: .recommended,
         auditVerdict: .green,
         minimumTier: .standard
     ),
     ```
4. `TinyLlama 1.1B Chat (MLX)`:
   - Lines 852–868:
     ```swift
     ModelCatalogItem(
         displayName: "TinyLlama 1.1B Chat (MLX)",
         family: .tinyLlama,
         variant: "4-bit MLX",
         summary: "Compact 1.1B parameters chat assistant optimized for standard edge devices.",
         parameterSize: "1.1B",
         quantization: "MLX 4-bit",
         diskSize: "~600 MB",
         contextWindow: "2K",
         runtimeType: .mlx,
         mlxModelID: "mlx-community/TinyLlama-1.1B-Chat-v1.0",
         recommendedForIPhone: true,
         runtimeStatus: .recommended,
         auditVerdict: .green,
         testedDeviceTier: .pro,
         minimumTier: .standard
     ),
     ```
5. `TinyLlama 1.1B Chat (GGUF)`:
   - Lines 869–883:
     ```swift
     ModelCatalogItem(
         displayName: "TinyLlama 1.1B Chat (GGUF)",
         family: .tinyLlama,
         variant: "Q4_K_M GGUF · Latest",
         summary: "TinyLlama 1.1B Chat model in GGUF format for llama.cpp runtime.",
         parameterSize: "1.1B",
         quantization: "GGUF Q4_K_M",
         diskSize: "~640 MB",
         contextWindow: "2K",
         downloadURL: URL(string: "https://huggingface.co/second-state/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf?download=true"),
         runtimeType: .gguf,
         runtimeStatus: .recommended,
         auditVerdict: .green,
         minimumTier: .standard
     ),
     ```

### 1.2 Legacy Profiles in `EdgeMindAi/Resources/RuntimeProfiles.json`
Direct inspection of `EdgeMindAi/Resources/RuntimeProfiles.json` verified the corresponding profiles:
- `B17E57C5-A066-56F1-834B-C2241E47DDF0` (Gemma 3 270M MLX): Lines 488–510
- `1F337B46-809D-5714-A125-58B78AB9332C` (StableLM 2 Zephyr MLX): Lines 977–999
- `C7F1DC4B-00E2-5ACD-B73A-4635168B582B` (StableLM 2 Zephyr GGUF): Lines 1000–1022
- `567E8C73-85A7-51EB-8295-0A0A5BB46608` (TinyLlama 1.1B MLX): Lines 1023–1045
- `95D57447-5590-56B1-AD76-547BAD7666CB` (TinyLlama 1.1B GGUF): Lines 1046–1068

### 1.3 State of Required 2026 Edge Lineup
Direct catalog inventory against `MockCatalogData.swift`:
- **VLMs**:
  - `Gemma 4 E2B Instruct (LiteRT-LM)`: Present (line 50)
  - `SmolVLM2 500M Instruct (MLX)`: Present (line 800)
  - `SmolVLM2 2.2B Instruct (MLX)`: **Missing**
  - `Qwen 3.5 VL 0.8B (MLX)`: Present (line 204)
  - `Qwen 3.5 VL 4B (MLX)`: Present (line 224)
  - `LFM2.5 VL 1.6B (MLX)`: Present (line 315)
- **Edge Text & Reasoning**:
  - `Qwen 3.5 0.8B Instruct (GGUF)`: Present (line 520)
  - `Qwen 3.5 2B Instruct (MLX)`: Present (line 498)
  - `Qwen 3.5 2B Instruct (GGUF)`: Present (line 538)
  - `Qwen 3 0.6B (MLX)`: Present (line 243)
  - `Qwen 3 1.7B (MLX)`: Present (line 261)
  - `Qwen 3 4B 2507 Thinking (MLX)`: Present (line 593)
  - `Qwen 3 4B 2507 Thinking (GGUF)`: Present (line 296)
  - `Qwen 3 0.6B (GGUF)`: **Missing**
  - `Qwen 3 1.7B (GGUF)`: **Missing**
  - `LFM2.5 350M (MLX)`: Present (line 335)
  - `LFM2.5 1.2B Thinking (MLX)`: Present (line 353)
  - `Granite 3.3 2B Instruct (MLX)`: Present (line 29)
  - `Granite 3.3 2B Instruct (GGUF)`: Present (line 612)
  - `Ministral 3 3B Instruct (MLX)`: Present (line 186)
  - `Ministral 3 3B Instruct (GGUF)`: Present (line 732)
  - `DeepSeek R1 Distill Qwen 1.5B (MLX)`: Present (line 167)
  - `DeepSeek R1 Distill Qwen 1.5B (GGUF)`: Present (line 751)
  - `Apple Intelligence`: Present (line 9)

### 1.4 Invariant Test Assertions
1. `RuntimeProfileTests.swift` lines 85–95 (`test_bundledJSONDoesNotContainStaleCatalogIDs`):
   Asserter verifies that every profile's `catalogID` exists in `MockCatalogData.items`.
2. `RuntimeProfileTests.swift` lines 37–43 (`test_bundledJSONLoads`):
   Asserter verifies that every chat item in `MockCatalogData.items` has a profile in `RuntimeProfileStore`.
3. `CatalogConsistencyTests.swift` lines 79–91 (`test_sameModelAcrossRuntimesAgreesOnContextWindow`):
   Asserts that models sharing a base name before `(` have identical `contextWindowTokenCount`.
4. `ModelCatalogItemTests.swift` lines 243–278 (`test_catalogFeaturesMajorOpenSourceProviderFamilies`):
   Asserts presence of required models for `.gemma`, `.llama`, `.phi`, `.deepSeek`, `.mistral`, and `.smolLM`.

---

## 2. Logic Chain

1. **Legacy Model Purge**:
   - *From Observation 1.1*: The 5 models (`TinyLlama` 1.1B MLX/GGUF, `StableLM` 2 Zephyr 1.6B MLX/GGUF, `Gemma` 3 270M MLX) are explicitly listed in `ORIGINAL_REQUEST.md` Requirement R2 as obsolete.
   - *From Observation 1.4.4*: `ModelCatalogItemTests.swift` does not test for or require `TinyLlama`, `StableLM`, or `Gemma 3 270M`.
   - *From Observation 1.4.1*: `test_bundledJSONDoesNotContainStaleCatalogIDs` fails if any profile exists in `RuntimeProfiles.json` without an item in `MockCatalogData.items`.
   - *Conclusion*: Removing the 5 models from `MockCatalogData.swift` and their 5 corresponding profiles (Observation 1.2) from `RuntimeProfiles.json` cleanly purges legacy weights while preserving all test suites.

2. **2026 Edge Model Parity**:
   - *From Observation 1.3*: `SmolVLM2 2.2B Instruct (MLX)`, `Qwen 3 0.6B (GGUF)`, and `Qwen 3 1.7B (GGUF)` are required by R2 but absent from the catalog.
   - *From Observation 1.4.3*: Any GGUF variant of `Qwen 3 0.6B` and `Qwen 3 1.7B` must specify `contextWindow: "40K"` to agree with their existing MLX siblings (`Qwen 3 0.6B (MLX)` and `Qwen 3 1.7B (MLX)`).
   - *From Observation 1.4.2*: Any new models added to `MockCatalogData.swift` must have corresponding profiles added to `RuntimeProfiles.json`.
   - *Conclusion*: Adding `SmolVLM2 2.2B Instruct (MLX)`, `Qwen 3 0.6B (GGUF)`, and `Qwen 3 1.7B (GGUF)` with matching context windows and synchronized profiles achieves complete R2 coverage without test regressions.

3. **Deterministic ID Stability**:
   - `DeterministicID.uuidV5` generates UUID v5 from `"\(displayName)::\(variant)"`.
   - The three existing explicit overrides on Gemma 4 (`671E127B-1ED4-59C5-A93F-A8730A25EAF3`, `9BD7F8CA-E895-5B96-8718-0BB5CB7FC186`, `A9A9D0A8-C083-49F1-8B8D-28D8A0F2B0B0`) are preserved to maintain compatibility with persisted `InstalledModel` entries.
   - New models omit `id:` to let `ModelCatalogItem` calculate their deterministic UUID v5 automatically.

---

## 3. Caveats

1. **Hardware Jetsam on 4B Vision Models**:
   As verified in `ModelRuntimeResolver.swift` (lines 20–25) and `MockCatalogData.swift` (line 88 and line 238), `Gemma 4 E4B` and `Qwen 3.5 VL 4B` have `sourceSupportsVision: true` but `supportsVision: false` (with `auditVerdict: .yellow(...)`). This reflects on-device Jetsam termination during image prefill on 8 GB devices. They must remain text-only in the app runtime until Apple Silicon memory pressure is mitigated.
2. **Xcode Project Re-generation**:
   As noted by Explorer 3, whenever new Swift files are added or `project.yml` is modified, `xcodegen generate` must be run so Xcode registers target membership.
3. **No Caveats on Purge Safety**:
   Purging the 5 legacy models has no adverse side effects on other components, as no service or view code references these specific models.

---

## 4. Conclusion

The model catalog and runtime profiles are well-structured and ready for the R2 modernization.
1. Purge the 5 legacy models from `MockCatalogData.swift` and their 5 profiles from `RuntimeProfiles.json`.
2. Add `SmolVLM2 2.2B Instruct (MLX)` (with `supportsVision: true`, 8K context, MLX 4-bit) and add its corresponding `imageAndText` profile in `RuntimeProfiles.json`.
3. Add `Qwen 3 0.6B (GGUF)` and `Qwen 3 1.7B (GGUF)` (both with `40K` context to match MLX siblings, Q4_K_M GGUF, Unsloth download URLs) and add their corresponding `qwenNative` thinking profiles in `RuntimeProfiles.json`.
4. Maintain explicit IDs on the 3 existing Gemma 4 models to avoid hash collision and broken installation tracking.

---

## 5. Verification Method

To independently verify the implementation:

1. **Catalog Consistency Suite**:
   ```bash
   xcodebuild test \
     -project EdgeMindAi.xcodeproj \
     -scheme EdgeMindAi \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
     -only-testing EdgeMindAiTests/CatalogConsistencyTests
   ```
   *Expected outcome*: 0 duplicate IDs (`test_allCatalogIDsAreUnique`), all models have valid load paths (`test_runtimeTypeHasWorkingLoadPath`), vision claims match input modes (`test_visionClaimMatchesInputModes`), and all cross-runtime siblings agree on context windows (`test_sameModelAcrossRuntimesAgreesOnContextWindow`).

2. **Runtime Profiles Suite**:
   ```bash
   xcodebuild test \
     -project EdgeMindAi.xcodeproj \
     -scheme EdgeMindAi \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
     -only-testing EdgeMindAiTests/RuntimeProfileTests
   ```
   *Expected outcome*: 100% of chat models have profiles (`test_bundledJSONLoads`), 0 stale profiles (`test_bundledJSONDoesNotContainStaleCatalogIDs`), and capability resolver passes for all models (`test_bundledProfilesEnableCatalogRuntimeCapabilities`).

3. **Model Catalog Suite & Core AI Compatibility**:
   ```bash
   xcodebuild test \
     -project EdgeMindAi.xcodeproj \
     -scheme EdgeMindAi \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
     -only-testing EdgeMindAiTests/ModelCatalogItemTests \
     -only-testing EdgeMindAiTests/CoreAIModelCompatibilityTests
   ```
   *Expected outcome*: All featured provider families pass, all Core AI presets map cleanly, and Pro memory budgets are respected.

4. **Invalidation Conditions**:
   - If any profile in `RuntimeProfiles.json` has a `catalogID` not in `MockCatalogData.swift`, `test_bundledJSONDoesNotContainStaleCatalogIDs` fails.
   - If any model in `MockCatalogData.swift` has `supportsVision: true` but `inputModes` lacks `.image`, `test_visionClaimMatchesInputModes` fails.
   - If any model with the same base name has conflicting context windows across GGUF and MLX, `test_sameModelAcrossRuntimesAgreesOnContextWindow` fails.
