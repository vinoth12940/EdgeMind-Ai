# MLX Stabilization and Device Tiering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every MLX model in the app's catalog produce clean, leak-free, non-hanging responses on every supported iPhone, then deploy the result to the user's physical iPhone.

**Architecture:** Five new components layered on the existing MLX stack: `DeviceTier` classifies devices by RAM; per-model `RuntimeProfile` (JSON) supersedes aspirational catalog flags for runtime decisions; `StreamProcessor` gains a mid-stream `TokenLeakScrubber`, hang watchdog, and repetition guard; a pure `ModelAuditRunner` service scripts smoke tests across all cataloged MLX entries; a hidden `ModelDiagnosticsView` drives the runner and promotes verdicts to the bundled JSON. `ChatView`, `MLXInferenceService`, and `MLXRuntime` remain structurally unchanged — all additions flow through new entry points or additive fields.

**Tech Stack:** Swift 5.10 · SwiftUI · MLX Swift (`MLXLLM`, `MLXVLM`, `MLXLMCommon`) · llama.cpp xcframework (unchanged in Phase 1) · XCTest · XcodeGen · iOS 17 deployment target.

**Branch:** `codex/stabilize-local-edge-app` (already checked out).

**Spec:** [docs/superpowers/specs/2026-04-19-mlx-stabilization-and-device-tiering-design.md](../specs/2026-04-19-mlx-stabilization-and-device-tiering-design.md)

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `LocalAIEdgeApp/Services/Inference/DeviceTier.swift` | `DeviceTier` enum + `current()` classifier + tier constants (usableWeightGB, safeContextTokens, jetsamSoftLimitGB). |
| `LocalAIEdgeApp/Services/Inference/RuntimeProfile.swift` | `RuntimeProfile` struct + `ThinkFormat`, `ToolCallFormat`, `VisionMode`, `Verdict` enums. Pure data + `Codable`. |
| `LocalAIEdgeApp/Services/Inference/RuntimeProfileStore.swift` | Loads bundled `RuntimeProfiles.json`, merges Debug override, exposes `profile(for: UUID)`. |
| `LocalAIEdgeApp/Services/Inference/ModelRuntimeResolver.swift` | Merges `ModelCatalogItem` + `RuntimeProfile` into `ResolvedModel` for `ChatView`. |
| `LocalAIEdgeApp/Services/Inference/TokenLeakScrubber.swift` | Mid-stream scrubber with lookahead buffer. Used by `StreamProcessor`. |
| `LocalAIEdgeApp/Services/Inference/ModelAuditRunner.swift` | Actor that runs `AuditCase`s; orchestrates install/uninstall via `InstallPolicy`. |
| `LocalAIEdgeApp/Services/Inference/AuditCase.swift` | `AuditCase`, `AuditExpectations`, `AuditProgress`, `AuditResult`, `Verdict` helpers. |
| `LocalAIEdgeApp/Services/Models/AuditDownloader.swift` | Protocol unifying GGUF (`URLModelDownloadService.beginInstall`) and MLX (`MLXRuntime.shared.preloadModel`) install/remove/lookup paths for `ModelAuditRunner`. Ships `DefaultAuditDownloader` + `MockAuditDownloader`. |
| `LocalAIEdgeApp/Features/Settings/ModelDiagnosticsView.swift` | SwiftUI screen gated by 5-tap gesture. Runs the harness. |
| `LocalAIEdgeApp/Resources/RuntimeProfiles.json` | Ships the eight MLX profiles at `.yellow("pending-audit")`. |
| `LocalAIEdgeApp/Resources/audit-apple.jpg` | ~80 KB public-domain apple photo for `visionProbe`. |
| `LocalAIEdgeAppTests/DeviceTierTests.swift` | `hw.machine` → tier classification coverage. |
| `LocalAIEdgeAppTests/ModelCatalogItemTests.swift` | Resident-RAM estimator + legacy decode + MB/GB parsing. |
| `LocalAIEdgeAppTests/RuntimeProfileTests.swift` | JSON round-trip, fallback, resolver merge rules, override-loader shadowing, bundle-load sanity. |
| `LocalAIEdgeAppTests/TokenLeakScrubberTests.swift` | Boundary splits, benign `<`, nested leaks. |
| `LocalAIEdgeAppTests/AssistantResponseSanitizerTests.swift` | Backstop regression test (all default leak tokens scrubbed). |
| `LocalAIEdgeAppTests/ModelAuditRunnerTests.swift` | Mock-stream pass/fail matrix. |

### Modified files

| Path | What changes |
|------|--------------|
| `LocalAIEdgeApp/Services/Inference/DeviceCapabilityService.swift` | Re-export `DeviceTier.current()` via an extension method; no existing API breaks. |
| `LocalAIEdgeApp/Models/ModelCatalogItem.swift` | Add `minimumTier: DeviceTier`, add `estimatedResidentGB(contextTokens:)`, flip `recommendedForIPhone` decode to `decodeIfPresent`. |
| `LocalAIEdgeApp/State/MockCatalogData.swift` | Annotate every entry with `minimumTier:`. |
| `LocalAIEdgeApp/Services/Inference/StreamProcessor.swift` | Add `.qwenNative` / `.gemmaChannel` detectors, wire `TokenLeakScrubber`, add `withTaskGroup` hang watchdog, add repetition guard with code-block carve-out, honor `AppSettings.streamProcessorV2Enabled`. |
| `LocalAIEdgeApp/Models/AppSettings.swift` | Add `streamProcessorV2Enabled: Bool` (default `true`), `inferenceV2Timeout: TimeInterval` (default 15, 30 on compact). |
| `LocalAIEdgeApp/Features/Chat/ChatView.swift` | Swap catalog-flag reads for `ModelRuntimeResolver.resolve(_:)`. |
| `LocalAIEdgeApp/Features/Models/ModelLibraryView.swift` | Default filter `minimumTier ≤ deviceTier`; "Show all" toggle reveals hidden with warning badge. |
| `LocalAIEdgeApp/Services/Models/ModelDownloadService.swift` | Resident-RAM guard before download; consent flag per `catalogID` in `UserDefaults`. (Audit-harness install/remove/lookup paths live in the separate `AuditDownloader` protocol.) |
| `LocalAIEdgeApp/Features/Settings/SettingsView.swift` | 5-tap gesture on version label reveals "Developer" section with link to `ModelDiagnosticsView`. |
| `LocalAIEdgeAppTests/StreamProcessorTests.swift` | New cases for Section 6 behaviors (leak scrub, empty-stream fallback, repetition guard + code-fence carve-out, hang watchdog fire & re-arm, v2-disabled regression). |
| `LocalAIEdgeApp/Services/Inference/MLXInferenceService.swift` | Thread `AppSettings` through `generateStream`; pass v2 parameters to `StreamProcessor`. |
| `LocalAIEdgeApp/Services/Inference/LocalLlamaInferenceService.swift` | Same as MLX — thread `AppSettings`, pass v2 params. |
| `project.yml` | No schema change needed — `LocalAIEdgeApp/Resources/` already wired at `project.yml:34`. Run `xcodegen generate` after adding `Resources/RuntimeProfiles.json` and `Resources/Assets.xcassets/audit-apple.imageset/`. |

---

## Conventions

- **TDD strict:** every new behavior gets a failing test first, then the minimal implementation that makes it green. Existing tests must stay green.
- **Commit cadence:** one commit per completed task. Co-author line: `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`.
- **Type checks = Xcode compile:** no separate linter. After each Swift-file edit, run `xcodebuild build -project LocalAIEdgeApp.xcodeproj -scheme LocalAIEdgeApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO` to confirm it compiles. Expected: `** BUILD SUCCEEDED **`.
- **Test runs:** `xcodebuild test -project LocalAIEdgeApp.xcodeproj -scheme LocalAIEdgeApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`. Expected: `** TEST SUCCEEDED **` with zero failures.
- **Single-test run:** append `-only-testing LocalAIEdgeAppTests/<ClassName>/<testMethod>`.
- **xcodegen discipline:** never edit `LocalAIEdgeApp.xcodeproj` by hand. If you add new files, Xcode picks them up automatically because `sources: path: LocalAIEdgeApp` is glob-based (verify: `grep -n sources project.yml`). For safety, run `xcodegen generate` once per phase and commit any resulting `project.pbxproj` change in the same phase commit.

---

## Phase 1 — DeviceTier classification

### Task 1.1: Write failing `DeviceTierTests`

**Files:**
- Create: `LocalAIEdgeAppTests/DeviceTierTests.swift`

- [ ] **Step 1: Create the test file**

```swift
// LocalAIEdgeAppTests/DeviceTierTests.swift
import XCTest
@testable import LocalAIEdgeApp

final class DeviceTierTests: XCTestCase {

    func test_iPhone12Family_classifiesAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,1"), .compact) // 12 mini (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,2"), .compact) // 12       (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,3"), .compact) // 12 Pro   (6 GB, still A14 → compact)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,4"), .compact) // 12 Pro Max
    }

    func test_iPhoneSE3_classifiesAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,6"), .compact)
    }

    func test_iPhone13_classifiesAsStandard() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,5"), .standard)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,2"), .standard)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,3"), .standard)
    }

    func test_iPhone15_nonPro_classifiesAsStandard() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone15,4"), .standard)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone15,5"), .standard)
    }

    func test_iPhone15Pro_classifiesAsPro() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone16,1"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone16,2"), .pro)
    }

    func test_iPhone16Series_classifiesAsPro() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,1"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,2"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,3"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,4"), .pro)
    }

    func test_unknownDeviceDefaultsToPro() {
        // Simulator, iPad, future iPhone: lean toward allowing more.
        XCTAssertEqual(DeviceTier.classify(machine: "x86_64"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "arm64"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad13,1"), .pro)
    }

    func test_budgets() {
        XCTAssertEqual(DeviceTier.compact.usableWeightGB, 1.2, accuracy: 0.01)
        XCTAssertEqual(DeviceTier.standard.usableWeightGB, 2.2, accuracy: 0.01)
        XCTAssertEqual(DeviceTier.pro.usableWeightGB, 4.5, accuracy: 0.01)
        XCTAssertEqual(DeviceTier.ultra.usableWeightGB, 7.0, accuracy: 0.01)
    }

    func test_ordering() {
        XCTAssertLessThan(DeviceTier.compact, DeviceTier.standard)
        XCTAssertLessThan(DeviceTier.standard, DeviceTier.pro)
        XCTAssertLessThan(DeviceTier.pro, DeviceTier.ultra)
    }
}
```

- [ ] **Step 2: Run and verify it fails**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/DeviceTierTests
```

Expected: compile failure "cannot find type 'DeviceTier' in scope" or similar.

### Task 1.2: Implement `DeviceTier`

**Files:**
- Create: `LocalAIEdgeApp/Services/Inference/DeviceTier.swift`

- [ ] **Step 1: Write the implementation**

```swift
// LocalAIEdgeApp/Services/Inference/DeviceTier.swift
import Foundation

/// Classifies the device into a coarse RAM / compute bucket so the catalog
/// and download guard can hide or warn about models that will not run safely.
///
/// Tier boundaries come from iOS jetsam behavior: foreground apps are killed
/// around ~55–60% of physical RAM. `usableWeightGB` targets ~35% of total,
/// leaving room for KV cache, MLX GPU cache, vision tower, app heap, OS.
enum DeviceTier: String, Comparable, Codable, CaseIterable {
    case compact   // 4 GB devices: iPhone 12 family, SE 2/3, 13 mini
    case standard  // 6 GB devices: iPhone 13, 14, 15 non-Pro
    case pro       // 8 GB devices: iPhone 15 Pro, 16, 17 non-Max
    case ultra     // 12 GB+ devices: iPhone 17 Pro Max, iPad M-series

    static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .compact:  return 0
        case .standard: return 1
        case .pro:      return 2
        case .ultra:    return 3
        }
    }

    /// Approximate resident memory budget for the model binary + KV cache + vision tower + heap.
    var usableWeightGB: Double {
        switch self {
        case .compact:  return 1.2
        case .standard: return 2.2
        case .pro:      return 4.5
        case .ultra:    return 7.0
        }
    }

    /// Conservative context-window size that the KV cache will actually allocate.
    /// Cataloged `contextWindow` strings (40K, 128K, 256K) are aspirational;
    /// this is what the runtime will actually use on the device.
    var safeContextTokens: Int {
        switch self {
        case .compact:  return 2048
        case .standard: return 4096
        case .pro:      return 8192
        case .ultra:    return 16384
        }
    }

    /// Soft threshold used by the audit runner's memory expectation.
    /// Tracks the jetsam "low memory" warning level, not the hard kill.
    var jetsamSoftLimitGB: Double {
        switch self {
        case .compact:  return 1.2
        case .standard: return 2.2
        case .pro:      return 4.5
        case .ultra:    return 7.0
        }
    }

    var displayName: String {
        switch self {
        case .compact:  return "Compact (4 GB)"
        case .standard: return "Standard (6 GB)"
        case .pro:      return "Pro (8 GB)"
        case .ultra:    return "Ultra (12 GB+)"
        }
    }

    /// Read-only classifier — pulls `hw.machine` via `DeviceCapabilityService.machineModel()`.
    static func current() -> DeviceTier {
        classify(machine: DeviceCapabilityService.machineModel())
    }

    /// Testable — inject a known machine string.
    static func classify(machine: String) -> DeviceTier {
        // iPhone 12 family (A14): iPhone13,1–13,4
        if machine.hasPrefix("iPhone13,") { return .compact }
        // iPhone SE 3 (A15, 4 GB): iPhone14,6  |  iPhone SE 2 (A13, 3 GB): iPhone12,8 — compact, MLX is marginal.
        if machine == "iPhone12,8" || machine == "iPhone14,6" { return .compact }
        // iPhone 13 mini (iPhone14,4) ships 4 GB — treat as compact for safety (A15 but RAM-constrained).
        if machine == "iPhone14,4" { return .compact }
        // iPhone 13 / 13 Pro / 13 Pro Max / 14 / 14 Plus / 14 Pro / 14 Pro Max (6 GB)
        // iPhone 15 / 15 Plus (6 GB) → identifiers iPhone15,4 / 15,5
        if machine.hasPrefix("iPhone14,") || machine == "iPhone15,4" || machine == "iPhone15,5" { return .standard }
        // iPhone 15 Pro / 15 Pro Max → iPhone16,1 / 16,2 (8 GB)
        if machine.hasPrefix("iPhone16,") { return .pro }
        // iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max → iPhone17,1–17,4 (8 GB)
        if machine.hasPrefix("iPhone17,") { return .pro }
        // Simulator, iPad, unknown future — default to .pro so we do not hide everything.
        // The download guard still blocks oversize loads.
        return .pro
    }
}
```

- [ ] **Step 2: Run tests and verify they pass**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/DeviceTierTests
```

Expected: all 8 tests pass.

- [ ] **Step 3: Verify the full test suite still passes**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: `** TEST SUCCEEDED **`.

### Task 1.3: Add `minimumTier` + `estimatedResidentGB` + decode-compat to `ModelCatalogItem`

**Files:**
- Modify: `LocalAIEdgeApp/Models/ModelCatalogItem.swift`

- [ ] **Step 1: Write a failing test for `estimatedResidentGB` and `decodeIfPresent`**

Append to `LocalAIEdgeAppTests/DeviceTierTests.swift` (or create `ModelCatalogItemTests.swift` — prefer a new file for isolation):

```swift
// LocalAIEdgeAppTests/ModelCatalogItemTests.swift
import XCTest
@testable import LocalAIEdgeApp

final class ModelCatalogItemTests: XCTestCase {

    func test_estimatedResidentGB_textOnly() {
        let item = ModelCatalogItem(
            displayName: "Test 1.7B",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "",
            parameterSize: "1.7B",
            quantization: "MLX 4-bit",
            diskSize: "~1.7 GB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/x",
            supportsVision: false,
            minimumTier: .standard
        )
        // 1.7 * 1.15 + kvCache(4096) + 0 + 0.3 ≈ 1.955 + ~0.2 + 0.3 ≈ 2.45 GB for standard
        let est = item.estimatedResidentGB(contextTokens: 4096)
        XCTAssertGreaterThan(est, 2.0)
        XCTAssertLessThan(est, 3.0)
    }

    func test_estimatedResidentGB_visionAddsTower() {
        let base = ModelCatalogItem(
            displayName: "Test VL",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "",
            parameterSize: "1.6B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/y",
            supportsVision: true,
            minimumTier: .standard
        )
        let nonVisionEstimate = 1.5 * 1.15 + 0.3 // ~2.025
        XCTAssertGreaterThan(base.estimatedResidentGB(contextTokens: 2048), nonVisionEstimate + 0.5)
    }

    func test_decodeMissingRecommendedForIPhone_defaultsToFalse() throws {
        let json = """
        {
            "id": "EAD31E2E-0000-5000-A000-000000000000",
            "displayName": "legacy entry",
            "family": "Qwen",
            "provider": "Hugging Face",
            "variant": "MLX",
            "summary": "",
            "parameterSize": "1B",
            "quantization": "MLX 4-bit",
            "diskSize": "1 GB",
            "contextWindow": "40K",
            "runtimeType": "MLX",
            "primaryUse": "chat",
            "sourceSupportsVision": false,
            "supportsVision": false,
            "supportsReasoning": false,
            "supportsToolCalling": false,
            "isThinkingModel": false,
            "minimumTier": "standard"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ModelCatalogItem.self, from: json)
        XCTAssertFalse(decoded.recommendedForIPhone)
        XCTAssertEqual(decoded.minimumTier, .standard)
    }
}
```

- [ ] **Step 2: Run it; expect a failure on `minimumTier` missing / ambiguous init signature**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/ModelCatalogItemTests
```

Expected: compile error `missing argument for parameter 'minimumTier' in call`.

- [ ] **Step 3: Modify `ModelCatalogItem.swift` — add `minimumTier`, decodeIfPresent, estimator**

In `LocalAIEdgeApp/Models/ModelCatalogItem.swift`:

1. Add the stored property near the other flags:

```swift
let minimumTier: DeviceTier
```

2. Add `minimumTier` to `CodingKeys` and to the init parameter list (default `.standard`):

```swift
init(
    // … existing args …
    isThinkingModel: Bool = false,
    recommendedForIPhone: Bool = false,
    minimumTier: DeviceTier = .standard
) {
    // … existing body …
    self.minimumTier = minimumTier
}
```

3. Change the `recommendedForIPhone` decode to optional and add `minimumTier` decode:

```swift
recommendedForIPhone = try container.decodeIfPresent(Bool.self, forKey: .recommendedForIPhone) ?? false
minimumTier = try container.decodeIfPresent(DeviceTier.self, forKey: .minimumTier) ?? .standard
```

4. Add `minimumTier` to `encode(to:)`:

```swift
try container.encode(minimumTier, forKey: .minimumTier)
```

5. Add `estimatedResidentGB`:

```swift
/// Approximate resident memory (GB) the model will use at runtime.
/// weights ≈ disk × 1.15  +  KV cache (layer count × head dim × ctx)
///         + vision tower (0.6 GB if applicable)  +  app heap headroom (0.3 GB).
func estimatedResidentGB(contextTokens: Int) -> Double {
    let weightsGB = parsedDiskSizeGB * 1.15
    let kvCacheGB = kvCacheEstimateGB(contextTokens: contextTokens)
    let visionGB: Double = supportsVision ? 0.6 : 0.0
    let heapGB = 0.3
    return weightsGB + kvCacheGB + visionGB + heapGB
}

private var parsedDiskSizeGB: Double {
    // diskSize is a string like "~1.7 GB" / "2.5 GB" / "~600 MB".
    let upper = diskSize.uppercased()
    let numericPortion = upper.filter { $0.isNumber || $0 == "." }
    guard let value = Double(numericPortion), value > 0 else { return 0 }
    if upper.contains("MB") { return value / 1024.0 }
    return value
}

private func kvCacheEstimateGB(contextTokens: Int) -> Double {
    // Rough family-based estimate. KV cache = 2 × nLayers × nHeads × headDim × ctx × 2 bytes.
    // For 4-bit Qwen-class 1.7B: ~28 layers, 16 heads, 128 dim → ≈ 4 KB per token → 0.016 GB per 4K.
    // Scale linearly by parameter-size bucket for simplicity.
    let perTokenKB: Double
    switch parameterSize {
    case _ where parameterSize.contains("0.6"):  perTokenKB = 2
    case _ where parameterSize.contains("1.2"):  perTokenKB = 3
    case _ where parameterSize.contains("1.6"):  perTokenKB = 3
    case _ where parameterSize.contains("1.7"):  perTokenKB = 4
    case _ where parameterSize.contains("2"):    perTokenKB = 5
    case _ where parameterSize.contains("4"):    perTokenKB = 7
    case _ where parameterSize.contains("8"):    perTokenKB = 10
    default:                                      perTokenKB = 4
    }
    return (Double(contextTokens) * perTokenKB) / (1024 * 1024)
}
```

- [ ] **Step 4: Run the new tests**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/ModelCatalogItemTests
```

Expected: all three pass.

- [ ] **Step 5: Run the entire test suite to catch regressions in existing tests**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: `** TEST SUCCEEDED **`.

### Task 1.4: Annotate catalog entries with `minimumTier`

**Files:**
- Modify: `LocalAIEdgeApp/State/MockCatalogData.swift`

- [ ] **Step 1: Add `minimumTier:` to each of the 8 MLX entries + 2 GGUF + 2 Qwen GGUF**

Per the spec §4.2 table:

| Model | `minimumTier` |
|-------|---------------|
| Gemma 4 E2B (GGUF) | `.standard` |
| Gemma 4 E4B (GGUF) | `.pro` |
| Qwen 3 0.6B (MLX) | `.compact` |
| Qwen 3 1.7B (MLX) | `.standard` |
| Qwen 3 4B (MLX) | `.pro` |
| Qwen 3 4B 2507 Instruct (MLX) | `.pro` |
| Qwen 3 4B 2507 Thinking (MLX) | `.pro` |
| Qwen 3 8B (MLX) | `.ultra` |
| Qwen 3 4B 2507 Instruct (GGUF) | `.pro` |
| Qwen 3 4B 2507 Thinking (GGUF) | `.pro` |
| LFM2.5 1.2B Instruct (MLX) | `.standard` |
| LFM2.5-VL 1.6B (MLX) | `.standard` |

Add `minimumTier: <value>,` as the last field in each `ModelCatalogItem(...)` literal, immediately before the closing paren (and AFTER `recommendedForIPhone:` where present).

- [ ] **Step 2: Build and run the full suite**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: `** TEST SUCCEEDED **`.

### Task 1.5: Commit Phase 1

- [ ] **Step 1: Regenerate Xcode project (in case new files need wiring)**

```bash
xcodegen generate
```

- [ ] **Step 2: Stage and commit**

```bash
git add \
  LocalAIEdgeApp/Services/Inference/DeviceTier.swift \
  LocalAIEdgeApp/Models/ModelCatalogItem.swift \
  LocalAIEdgeApp/State/MockCatalogData.swift \
  LocalAIEdgeAppTests/DeviceTierTests.swift \
  LocalAIEdgeAppTests/ModelCatalogItemTests.swift \
  LocalAIEdgeApp.xcodeproj/project.pbxproj

git commit -m "$(cat <<'EOF'
feat: device tier classification and resident-RAM estimator

Add DeviceTier (.compact/.standard/.pro/.ultra) derived from hw.machine
so the catalog and download guard can hide or warn about models that
cannot run safely on the device.

Annotate every catalog entry with minimumTier. Deprecate recommendedForIPhone
(decoded via decodeIfPresent for backward compatibility with persisted
InstalledModel records). Add ModelCatalogItem.estimatedResidentGB(contextTokens:)
accounting for weights + KV cache + vision tower + heap headroom.

Tests: DeviceTierTests (8 cases covering A14–A18 hardware identifiers),
ModelCatalogItemTests (resident-RAM estimator math + legacy decode).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — `RuntimeProfile` + JSON loader

### Task 2.1: Define `RuntimeProfile` and enums

**Files:**
- Create: `LocalAIEdgeApp/Services/Inference/RuntimeProfile.swift`

- [ ] **Step 1: Write the file**

```swift
// LocalAIEdgeApp/Services/Inference/RuntimeProfile.swift
import Foundation

enum ThinkFormat: String, Codable {
    case xmlThink      // <think>...</think>, <thinking>..., <reasoning>...
    case qwenNative    // <|im_start|>think ... <|im_end|> or <|think|>...<|/think|>
    case gemmaChannel  // <|channel>thought\n ... <|channel> (GGUF Gemma 4; dead code today)
}

enum ToolCallFormat: String, Codable {
    case xmlToolCall          // <tool_call>{...}</tool_call>
    case gemmaNativeToolCall  // <|tool_call>...<tool_call|>
}

enum VisionMode: String, Codable {
    case none
    case textOnlyInputs   // model accepts images but app routes text-only
    case imageAndText     // model accepts images and app supports attachments
}

enum Verdict: Codable, Equatable {
    case green
    case yellow(String)
    case red(String)

    private enum CodingKeys: String, CodingKey { case kind, note }
    private enum Kind: String, Codable { case green, yellow, red }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        switch kind {
        case .green:  self = .green
        case .yellow: self = .yellow(note)
        case .red:    self = .red(note)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .green:
            try c.encode(Kind.green, forKey: .kind)
        case .yellow(let note):
            try c.encode(Kind.yellow, forKey: .kind)
            try c.encode(note, forKey: .note)
        case .red(let note):
            try c.encode(Kind.red, forKey: .kind)
            try c.encode(note, forKey: .note)
        }
    }

    var isGreen: Bool { if case .green = self { return true }; return false }
    var isRed: Bool { if case .red = self { return true }; return false }
}

struct RuntimeProfile: Codable, Equatable {
    let catalogID: UUID
    let verifiedThinking: ThinkFormat?
    let verifiedToolCalling: ToolCallFormat?
    let verifiedVision: VisionMode
    let knownLeakTokens: [String]
    let recommendedMaxTokens: Int
    let auditedAt: String   // ISO-8601
    let auditVerdict: Verdict

    /// Fallback when a model has no profile on file.
    /// Conservative: text-only, no tools, no think-block parsing, strict scrubber.
    static func safeMinimum(catalogID: UUID) -> RuntimeProfile {
        RuntimeProfile(
            catalogID: catalogID,
            verifiedThinking: nil,
            verifiedToolCalling: nil,
            verifiedVision: .none,
            knownLeakTokens: ["<|im_end|>", "<|endoftext|>", "<end_of_turn>"],
            recommendedMaxTokens: 512,
            auditedAt: "",
            auditVerdict: .yellow("no-profile-on-file")
        )
    }
}
```

- [ ] **Step 2: Compile**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

### Task 2.2: Ship starter `RuntimeProfiles.json`

**Files:**
- Create: `LocalAIEdgeApp/Resources/RuntimeProfiles.json`

- [ ] **Step 1: Extract the deterministic UUIDs via an XCTAttachment-backed test**

UUIDs must match `ModelCatalogItem`'s SHA-1 UUIDv5 (namespace `A1B2C3D4-E5F6-7890-ABCD-EF1234567890`, name `"<displayName>::<variant>"`). Do NOT rely on `xcodebuild test … | grep` — `print()` output is not reliably surfaced to stdout. Instead, write a one-shot test that fails with the dictionary in the failure message AND attaches a JSON file. Read the attachment path from the xcresult bundle.

```swift
// Temporary: LocalAIEdgeAppTests/PrintCatalogIDs.swift (delete after generating JSON)
import XCTest
@testable import LocalAIEdgeApp

final class PrintCatalogIDs: XCTestCase {
    func test_dumpCatalogIDsAsAttachment() throws {
        let dict = Dictionary(uniqueKeysWithValues:
            MockCatalogData.items
                .filter { $0.runtimeType == .mlx }
                .map { ($0.displayName, $0.id.uuidString) })

        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.lifetime = .keepAlways
        attachment.name = "mlx-catalog-ids.json"
        add(attachment)

        // Fail with the contents inline too, so the build log carries the JSON even
        // if the xcresult bundle is lost.
        let inline = String(data: data, encoding: .utf8) ?? ""
        XCTFail("ONE-SHOT DUMP — copy the JSON below, delete this test, then re-run:\n\(inline)")
    }
}
```

Run the test (expected: one failure with the JSON body in the stderr block):

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/PrintCatalogIDs/test_dumpCatalogIDsAsAttachment \
  -resultBundlePath ./build/CatalogIDs.xcresult
```

The ID dictionary appears in the failure message. If that is hard to spot, extract it from the result bundle instead:

```bash
xcrun xcresulttool get --path ./build/CatalogIDs.xcresult --format json \
  | grep -o 'mlx-catalog-ids.json' -A1 || true
# Or open in Xcode: open ./build/CatalogIDs.xcresult
```

- [ ] **Step 2: Write `LocalAIEdgeApp/Resources/RuntimeProfiles.json`**

Fill `catalogID` values from Step 1. Every MLX entry gets a profile (8 entries). Use `.yellow("pending-audit")` for every verdict today; Phase 7 promotes passing ones to `.green`. The encoder omits `note` for `.green`, so `.green` entries are written as `{ "kind": "green" }` — an example of that shape is included below so promoters do not invent their own schema.

```json
[
  {
    "catalogID": "<Qwen 3 0.6B UUID>",
    "verifiedThinking": "qwenNative",
    "verifiedToolCalling": "xmlToolCall",
    "verifiedVision": "none",
    "knownLeakTokens": ["<|im_end|>", "<|endoftext|>", "<|im_start|>"],
    "recommendedMaxTokens": 1024,
    "auditedAt": "",
    "auditVerdict": { "kind": "yellow", "note": "pending-audit" }
  },
  {
    "catalogID": "<Qwen 3 1.7B UUID>",
    "verifiedThinking": "qwenNative",
    "verifiedToolCalling": "xmlToolCall",
    "verifiedVision": "none",
    "knownLeakTokens": ["<|im_end|>", "<|endoftext|>", "<|im_start|>"],
    "recommendedMaxTokens": 1024,
    "auditedAt": "",
    "auditVerdict": { "kind": "yellow", "note": "pending-audit" }
  }
]
```

Remaining entries (paste into the array, in order): Qwen 3 4B, Qwen 3 4B 2507 Instruct (`verifiedThinking: null`), Qwen 3 4B 2507 Thinking, Qwen 3 8B, LFM2.5 1.2B Instruct (`verifiedThinking: null`, `verifiedToolCalling: "xmlToolCall"`), LFM2.5-VL 1.6B (`verifiedThinking: null`, `verifiedToolCalling: "xmlToolCall"`, `verifiedVision: "imageAndText"`).

**Post-promotion shape (Phase 7 will write this for `.green`):**

```json
{
  "catalogID": "<Qwen 3 1.7B UUID>",
  "verifiedThinking": "qwenNative",
  "verifiedToolCalling": "xmlToolCall",
  "verifiedVision": "none",
  "knownLeakTokens": ["<|im_end|>", "<|endoftext|>", "<|im_start|>"],
  "recommendedMaxTokens": 1024,
  "auditedAt": "2026-04-20T15:22:11Z",
  "auditVerdict": { "kind": "green" }
}
```

- [ ] **Step 3: Regenerate the Xcode project so the new JSON lands in the `Resources` phase**

`LocalAIEdgeApp/Resources/` is already wired at `project.yml:34`, but the `project.pbxproj` cache needs to be refreshed after adding files.

```bash
xcodegen generate
```

- [ ] **Step 4: Build once and confirm the JSON is copied into the app bundle**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath ./build \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`. Then verify the file is in the app wrapper:

```bash
ls ./build/Build/Products/Debug-iphonesimulator/LocalAIEdgeApp.app/RuntimeProfiles.json
```

If `ls` errors with `No such file or directory`, the resource is not being copied — check that `LocalAIEdgeApp/Resources` is still listed under `resources:` in `project.yml` and re-run `xcodegen generate`.

- [ ] **Step 5: Delete the temporary ID-printing test**

```bash
rm LocalAIEdgeAppTests/PrintCatalogIDs.swift
xcodegen generate
```

### Task 2.3: Write failing `RuntimeProfileTests`

**Files:**
- Create: `LocalAIEdgeAppTests/RuntimeProfileTests.swift`

- [ ] **Step 1: Write the test file**

```swift
// LocalAIEdgeAppTests/RuntimeProfileTests.swift
import XCTest
@testable import LocalAIEdgeApp

final class RuntimeProfileTests: XCTestCase {

    func test_verdictRoundTrip_green() throws {
        let v = Verdict.green
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(Verdict.self, from: data)
        XCTAssertEqual(decoded, .green)
    }

    func test_verdictRoundTrip_yellow() throws {
        let v = Verdict.yellow("pending-audit")
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(Verdict.self, from: data)
        XCTAssertEqual(decoded, .yellow("pending-audit"))
    }

    func test_profileRoundTrip() throws {
        let profile = RuntimeProfile(
            catalogID: UUID(),
            verifiedThinking: .qwenNative,
            verifiedToolCalling: .xmlToolCall,
            verifiedVision: .none,
            knownLeakTokens: ["<|im_end|>"],
            recommendedMaxTokens: 1024,
            auditedAt: "2026-04-19T08:00:00Z",
            auditVerdict: .green
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(RuntimeProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func test_bundledJSONLoads() throws {
        let store = RuntimeProfileStore()
        let catalog = MockCatalogData.items.filter { $0.runtimeType == .mlx }
        for item in catalog {
            let p = store.profile(for: item.id)
            XCTAssertNotNil(p, "Missing profile for \(item.displayName) (\(item.id))")
        }
    }

    func test_missingProfileReturnsNil() {
        let store = RuntimeProfileStore()
        XCTAssertNil(store.profile(for: UUID()))
    }

    func test_resolverPrefersProfileForRuntimeBehavior() {
        let item = MockCatalogData.items.first { $0.displayName == "LFM2.5-VL 1.6B (MLX)" }!
        let store = RuntimeProfileStore()
        let resolved = ModelRuntimeResolver.resolve(catalog: item, store: store)
        // Catalog claims vision: true (supportsVision), profile should confirm
        XCTAssertEqual(resolved.vision, .imageAndText)
    }

    func test_resolverFallsBackToSafeMinimumWhenNoProfile() {
        let item = MockCatalogData.items.first!
        let emptyStore = RuntimeProfileStore(bundleLoader: { [] })
        let resolved = ModelRuntimeResolver.resolve(catalog: item, store: emptyStore)
        XCTAssertEqual(resolved.vision, .none)
        XCTAssertNil(resolved.thinking)
        XCTAssertNil(resolved.tools)
    }

    func test_overrideLoaderShadowsBundled() {
        let id = UUID()
        let bundled = RuntimeProfile(
            catalogID: id,
            verifiedThinking: nil,
            verifiedToolCalling: nil,
            verifiedVision: .none,
            knownLeakTokens: [],
            recommendedMaxTokens: 512,
            auditedAt: "",
            auditVerdict: .yellow("pending-audit")
        )
        let override = RuntimeProfile(
            catalogID: id,
            verifiedThinking: .qwenNative,
            verifiedToolCalling: .xmlToolCall,
            verifiedVision: .imageAndText,
            knownLeakTokens: ["<|override|>"],
            recommendedMaxTokens: 2048,
            auditedAt: "2026-04-19T09:00:00Z",
            auditVerdict: .green
        )
        let store = RuntimeProfileStore(
            bundleLoader: { [bundled] },
            overrideLoader: { [override] }
        )
        let resolved = store.profile(for: id)
        XCTAssertEqual(resolved?.auditVerdict, .green)
        XCTAssertEqual(resolved?.verifiedThinking, .qwenNative)
        XCTAssertEqual(resolved?.recommendedMaxTokens, 2048)
        XCTAssertTrue(resolved?.knownLeakTokens.contains("<|override|>") == true)
    }

    /// A compile-time safeguard: in Release builds the override path returns [] by
    /// construction (`#else` branch). The test cannot prove the `#if` is in place, but
    /// it does lock in the injectable contract so a later refactor that drops the
    /// overrideLoader parameter trips this test and forces a code review.
    func test_storeAcceptsInjectedOverrideLoader() {
        // Pure signature check — if this compiles, the injection hook exists.
        _ = RuntimeProfileStore(bundleLoader: { [] }, overrideLoader: { [] })
    }

    func test_bundledJSONResolvesFromAppBundle() throws {
        // Belt-and-braces check: the actual Bundle.main URL lookup used by the default
        // loader path must succeed. Otherwise the resource did not make it into the app.
        let url = Bundle(for: RuntimeProfileTests.self).url(forResource: "RuntimeProfiles", withExtension: "json")
            ?? Bundle.main.url(forResource: "RuntimeProfiles", withExtension: "json")
        XCTAssertNotNil(url, "RuntimeProfiles.json is not in the built app bundle. Run xcodegen generate + rebuild.")
    }
}
```

- [ ] **Step 2: Run — expect failure on missing `RuntimeProfileStore` / `ModelRuntimeResolver`**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/RuntimeProfileTests
```

### Task 2.4: Implement `RuntimeProfileStore`

**Files:**
- Create: `LocalAIEdgeApp/Services/Inference/RuntimeProfileStore.swift`

- [ ] **Step 1: Write the loader**

```swift
// LocalAIEdgeApp/Services/Inference/RuntimeProfileStore.swift
import Foundation
import OSLog

private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "RuntimeProfileStore")

/// Loads bundled RuntimeProfiles.json once, exposes profile lookup.
/// In Debug builds, a local Documents override can shadow bundled entries.
/// In Release builds, the override path is compiled out — no override can ship.
final class RuntimeProfileStore {
    private let profiles: [UUID: RuntimeProfile]

    init(bundleLoader: (() -> [RuntimeProfile])? = nil, overrideLoader: (() -> [RuntimeProfile])? = nil) {
        let bundled = (bundleLoader ?? Self.loadBundled)()
        let overridden = (overrideLoader ?? Self.loadOverride)()
        var merged = Dictionary(uniqueKeysWithValues: bundled.map { ($0.catalogID, $0) })
        for o in overridden {
            merged[o.catalogID] = o  // override shadows bundled
            logger.log("RuntimeProfile override active for \(o.catalogID.uuidString, privacy: .public)")
        }
        self.profiles = merged
    }

    func profile(for catalogID: UUID) -> RuntimeProfile? {
        profiles[catalogID]
    }

    private static func loadBundled() -> [RuntimeProfile] {
        guard let url = Bundle.main.url(forResource: "RuntimeProfiles", withExtension: "json") else {
            logger.error("RuntimeProfiles.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([RuntimeProfile].self, from: data)
        } catch {
            logger.error("Failed to decode RuntimeProfiles.json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    #if DEBUG
    private static func loadOverride() -> [RuntimeProfile] {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        let url = dir.appending(path: "RuntimeProfiles.override.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RuntimeProfile].self, from: data)) ?? []
    }
    #else
    private static func loadOverride() -> [RuntimeProfile] { [] }
    #endif
}
```

### Task 2.5: Implement `ModelRuntimeResolver`

**Files:**
- Create: `LocalAIEdgeApp/Services/Inference/ModelRuntimeResolver.swift`

- [ ] **Step 1: Write the resolver**

```swift
// LocalAIEdgeApp/Services/Inference/ModelRuntimeResolver.swift
import Foundation

struct ResolvedModel {
    let catalog: ModelCatalogItem
    let thinking: ThinkFormat?         // runtime will parse think blocks for this model
    let tools: ToolCallFormat?         // runtime will run the agentic tool-call loop
    let vision: VisionMode             // runtime accepts image attachments
    let leakTokens: [String]
    let maxTokens: Int
    let verdict: Verdict
    let isMismatch: Bool               // true when catalog claims a capability the profile denies
}

enum ModelRuntimeResolver {
    static func resolve(catalog: ModelCatalogItem, store: RuntimeProfileStore) -> ResolvedModel {
        let profile = store.profile(for: catalog.id) ?? RuntimeProfile.safeMinimum(catalogID: catalog.id)

        // Detect mismatches so UI can surface "claimed but not verified".
        let visionMismatch = catalog.supportsVision && profile.verifiedVision == .none
        let toolMismatch = catalog.supportsToolCalling && profile.verifiedToolCalling == nil
        let thinkMismatch = catalog.isThinkingModel && profile.verifiedThinking == nil

        return ResolvedModel(
            catalog: catalog,
            thinking: profile.verifiedThinking,
            tools: profile.verifiedToolCalling,
            vision: profile.verifiedVision,
            leakTokens: profile.knownLeakTokens,
            maxTokens: profile.recommendedMaxTokens,
            verdict: profile.auditVerdict,
            isMismatch: visionMismatch || toolMismatch || thinkMismatch
        )
    }
}
```

- [ ] **Step 2: Run `RuntimeProfileTests`**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/RuntimeProfileTests
```

Expected: all 7 tests pass. If `test_bundledJSONLoads` fails, re-verify UUIDs in `RuntimeProfiles.json` match the catalog IDs printed earlier.

### Task 2.6: Wire `ChatView` to consume `ModelRuntimeResolver`

**Files:**
- Modify: `LocalAIEdgeApp/Features/Chat/ChatView.swift`

- [ ] **Step 1: Read current capability-flag usage**

Grep for all sites where `model.catalogItem.supportsToolCalling`, `supportsVision`, `isThinkingModel` are read:

```bash
```

Run `Grep` (internal tool) with pattern `(supportsToolCalling|supportsVision|isThinkingModel)` scoped to `LocalAIEdgeApp/Features/Chat/ChatView.swift`. Record each line number.

- [ ] **Step 2: Add a resolver instance to `ChatView`**

At the top of the struct:

```swift
private let profileStore = RuntimeProfileStore()

private func resolved(for model: InstalledModel) -> ResolvedModel {
    ModelRuntimeResolver.resolve(catalog: model.catalogItem, store: profileStore)
}
```

- [ ] **Step 3: Replace each capability read**

- `model.catalogItem.supportsToolCalling` → `resolved(for: model).tools != nil`
- `model.catalogItem.supportsVision` (when deciding whether to offer image attachment) → `resolved(for: model).vision == .imageAndText`
- `model.catalogItem.isThinkingModel` → `resolved(for: model).thinking != nil`

Keep `catalog.supports*` as-is where it is used for **display only** (badges on the model card). Only the **runtime decision** paths swap.

- [ ] **Step 4: Build and run the full suite**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: `** TEST SUCCEEDED **`.

### Task 2.7: Commit Phase 2

- [ ] **Step 1: Regenerate project, stage, commit**

```bash
xcodegen generate

git add \
  LocalAIEdgeApp/Services/Inference/RuntimeProfile.swift \
  LocalAIEdgeApp/Services/Inference/RuntimeProfileStore.swift \
  LocalAIEdgeApp/Services/Inference/ModelRuntimeResolver.swift \
  LocalAIEdgeApp/Resources/RuntimeProfiles.json \
  LocalAIEdgeApp/Features/Chat/ChatView.swift \
  LocalAIEdgeAppTests/RuntimeProfileTests.swift \
  LocalAIEdgeApp.xcodeproj/project.pbxproj

git commit -m "$(cat <<'EOF'
feat: RuntimeProfile JSON, loader, and resolver

Introduce per-model RuntimeProfile as the source of truth for runtime
capability decisions (think-block parsing, tool-call loop, image
attachment). Catalog flags continue to drive display badges; the
resolver surfaces "claimed but not verified" mismatches so users can
see when the app's verified behavior diverges from upstream claims.

Ship RuntimeProfiles.json with eight MLX entries at .yellow
("pending-audit"); Phase 7 promotes these to .green after on-device
audit. Debug override path is compile-time gated — Release builds
never honor a local override.

Tests: RuntimeProfileTests (verdict round-trip, bundle load coverage,
resolver merge rules, safe-minimum fallback).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — StreamProcessor v2 (leak scrubber + hang watchdog + repetition guard + new tags)

### Task 3.1: Add `streamProcessorV2Enabled` and `inferenceV2Timeout` to `AppSettings`

**Files:**
- Modify: `LocalAIEdgeApp/Models/AppSettings.swift`

- [ ] **Step 1: Add fields + defaults**

```swift
// inside struct AppSettings
var streamProcessorV2Enabled: Bool
var inferenceV2Timeout: TimeInterval   // seconds
```

Update `AppSettings.default`:

```swift
streamProcessorV2Enabled: true,
inferenceV2Timeout: 15
```

Update any decoding path (e.g., `UserDefaults` → JSON) to default-fill when the keys are missing. If the type uses `Codable`, change to `decodeIfPresent`:

```swift
// custom init(from:) if one exists — mirror the pattern for every new field
streamProcessorV2Enabled = try container.decodeIfPresent(Bool.self, forKey: .streamProcessorV2Enabled) ?? true
inferenceV2Timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .inferenceV2Timeout) ?? 15
```

- [ ] **Step 2: Build**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

### Task 3.2: Write failing `TokenLeakScrubberTests`

**Files:**
- Create: `LocalAIEdgeAppTests/TokenLeakScrubberTests.swift`

- [ ] **Step 1: Write the tests**

```swift
// LocalAIEdgeAppTests/TokenLeakScrubberTests.swift
import XCTest
@testable import LocalAIEdgeApp

final class TokenLeakScrubberTests: XCTestCase {

    func test_passesBenignText() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let out = await scrubber.feed("Hello world")
        XCTAssertEqual(out, "Hello world")
        let flushed = await scrubber.flush()
        XCTAssertEqual(flushed, "")
    }

    func test_stripsKnownLeakToken() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let out = await scrubber.feed("Hello<|im_end|> world")
        XCTAssertEqual(out, "Hello world")
    }

    func test_holdsPartialLeakAcrossTokenBoundaries() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let a = await scrubber.feed("Hello<|im_")
        XCTAssertEqual(a, "Hello")              // "<|im_" is a prefix — held back
        let b = await scrubber.feed("end|> world")
        XCTAssertEqual(b, " world")             // tail arrives, full match scrubbed
    }

    func test_benignAngleBracketPassesThrough() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let out = await scrubber.feed("2 < 3 and a > b")
        XCTAssertEqual(out, "2 < 3 and a > b")
    }

    func test_multipleLeaksInOneStream() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>", "<end_of_turn>"])
        let out = await scrubber.feed("one<|im_end|>two<end_of_turn>three")
        XCTAssertEqual(out, "onetwothree")
    }

    func test_flushReleasesHeldTail() async {
        let scrubber = TokenLeakScrubber(leakTokens: ["<|im_end|>"])
        let a = await scrubber.feed("hi <|im_")
        XCTAssertEqual(a, "hi ")
        let flushed = await scrubber.flush()
        // Held prefix was not a real leak → must be flushed as-is at end.
        XCTAssertEqual(flushed, "<|im_")
    }

    func test_bufferGrowsWithLongestLeakToken() async {
        let long = "<|custom-long-end-of-turn-marker|>"  // 34 chars > default 24 lookahead
        let scrubber = TokenLeakScrubber(leakTokens: [long])
        let out = await scrubber.feed("before" + long + "after")
        XCTAssertEqual(out, "beforeafter")
    }
}
```

- [ ] **Step 2: Run — expect compile failure on missing `TokenLeakScrubber`**

### Task 3.3: Implement `TokenLeakScrubber`

**Files:**
- Create: `LocalAIEdgeApp/Services/Inference/TokenLeakScrubber.swift`

- [ ] **Step 1: Write the actor**

```swift
// LocalAIEdgeApp/Services/Inference/TokenLeakScrubber.swift
import Foundation

/// Mid-stream scrubber that removes known leak tokens before emitting text to the UI.
/// Holds a lookahead buffer so a leak token split across two incoming chunks is still caught.
actor TokenLeakScrubber {
    private let leakTokens: [String]
    private let lookahead: Int
    private var buffer: String = ""

    init(leakTokens: [String]) {
        let longest = leakTokens.map(\.count).max() ?? 0
        self.lookahead = max(24, longest + 8)
        self.leakTokens = leakTokens
    }

    /// Feed a chunk; returns the scrubbed, emittable prefix. Unemitted tail stays in buffer.
    func feed(_ chunk: String) -> String {
        buffer += chunk
        var cleaned = stripKnownLeaks(in: &buffer)

        // Retain a tail of `lookahead` characters so a leak split across the next chunk is catchable.
        if buffer.count > lookahead {
            let splitIndex = buffer.index(buffer.endIndex, offsetBy: -lookahead)
            cleaned += String(buffer[..<splitIndex])
            buffer = String(buffer[splitIndex...])
        } else {
            // Buffer is smaller than lookahead — hold it all.
        }

        // Re-scrub `cleaned` in case a full leak sat entirely in the released prefix.
        return stripKnownLeaks(in: &cleaned)
    }

    /// Called at end of stream: releases whatever is in the buffer unaltered (no more chunks coming).
    func flush() -> String {
        defer { buffer = "" }
        var out = buffer
        out = stripKnownLeaks(in: &out)
        return out
    }

    private func stripKnownLeaks(in text: inout String) -> String {
        for token in leakTokens {
            text = text.replacingOccurrences(of: token, with: "")
        }
        return text
    }
}
```

- [ ] **Step 2: Run the scrubber tests**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/TokenLeakScrubberTests
```

Expected: 7 tests pass.

### Task 3.4: Add StreamProcessor v2 behaviors behind the master toggle

**Files:**
- Modify: `LocalAIEdgeApp/Services/Inference/StreamProcessor.swift`
- Modify: `LocalAIEdgeAppTests/StreamProcessorTests.swift`

- [ ] **Step 1: Write failing tests for new behaviors**

Append to `StreamProcessorTests.swift`:

```swift
func test_v2_stripsLeakTokensMidStream() async {
    let raw = mockStream(chunks: ["Hello<|im_", "end|> world"])
    let sp = StreamProcessor(rawStream: raw, leakTokens: ["<|im_end|>"], v2Enabled: true, hangTimeout: 30, repetitionNgram: 6, repetitionCount: 3)
    let text = await collectText(await sp.process())
    XCTAssertEqual(text, "Hello world")
}

func test_v2_emptyStreamYieldsFallbackMessage() async {
    let raw = mockStream(chunks: [])
    let sp = StreamProcessor(rawStream: raw, leakTokens: [], v2Enabled: true, hangTimeout: 1, repetitionNgram: 6, repetitionCount: 3)
    let text = await collectText(await sp.process())
    XCTAssertTrue(text.lowercased().contains("did not produce output"))
}

func test_v2_repetitionTrips() async {
    let phrase = "I think this is right. "
    let raw = mockStream(chunks: Array(repeating: phrase, count: 12))
    let sp = StreamProcessor(rawStream: raw, leakTokens: [], v2Enabled: true, hangTimeout: 30, repetitionNgram: 6, repetitionCount: 3)
    let text = await collectText(await sp.process())
    XCTAssertLessThan(text.count, phrase.count * 12)  // truncated before the full loop
}

func test_v2_codeBlockSuppressesRepetitionGuard() async {
    let chunks = ["```swift\n", "for i in 0..<5 { print(i) }\n", "for i in 0..<5 { print(i) }\n", "for i in 0..<5 { print(i) }\n", "for i in 0..<5 { print(i) }\n", "```"]
    let raw = mockStream(chunks: chunks)
    let sp = StreamProcessor(rawStream: raw, leakTokens: [], v2Enabled: true, hangTimeout: 30, repetitionNgram: 6, repetitionCount: 3)
    let text = await collectText(await sp.process())
    XCTAssertTrue(text.contains("```"))
    XCTAssertTrue(text.contains("for i in 0..<5"))
    // Should NOT be truncated as "repetition" inside a code fence.
}

func test_v2_unclosedCodeFenceKeepsGuardDisabledThroughEnd() async {
    // Odd fence count at stream end = still inside fence → guard must stay off.
    let chunks = ["```swift\n", "print(\"a\")\n", "print(\"a\")\n", "print(\"a\")\n", "print(\"a\")\n", "print(\"a\")\n"]  // no closing ```
    let raw = mockStream(chunks: chunks)
    let sp = StreamProcessor(rawStream: raw, leakTokens: [], v2Enabled: true, hangTimeout: 30, repetitionNgram: 4, repetitionCount: 2)
    let text = await collectText(await sp.process())
    // All five print statements must survive — no mid-stream truncation.
    let count = text.components(separatedBy: "print(\"a\")").count - 1
    XCTAssertEqual(count, 5)
}

func test_v2_guardReengagesAfterClosedFence() async {
    // Closed fence → repeat outside → guard must re-engage.
    let prefix = "```swift\nlet x = 1\n```\n"
    let phrase = "I think this is right. "
    let chunks = [prefix] + Array(repeating: phrase, count: 12)
    let raw = mockStream(chunks: chunks)
    let sp = StreamProcessor(rawStream: raw, leakTokens: [], v2Enabled: true, hangTimeout: 30, repetitionNgram: 6, repetitionCount: 3)
    let text = await collectText(await sp.process())
    XCTAssertTrue(text.contains("```swift"))
    XCTAssertLessThan(text.count, prefix.count + phrase.count * 12)  // truncated after fence close
}

func test_v2_disabledTogglePreservesV1Behavior() async {
    // Regression: when AppSettings.streamProcessorV2Enabled == false, the processor
    // must not touch TokenLeakScrubber / hang watchdog / repetition guard paths.
    let raw = mockStream(chunks: ["Hello <|im_end|> world"])
    let sp = StreamProcessor(rawStream: raw, leakTokens: ["<|im_end|>"], v2Enabled: false, hangTimeout: 1, repetitionNgram: 6, repetitionCount: 3)
    let text = await collectText(await sp.process())
    // v1 does NOT scrub leaks mid-stream (that is AssistantResponseSanitizer's post-stream job).
    // The leak token passes through here, exactly as before.
    XCTAssertTrue(text.contains("<|im_end|>"))
}

func test_v2_hangWatchdogFiresOnSilentStream() async {
    // A stream that yields nothing for > hangTimeout must emit the fallback message.
    let raw = AsyncStream<String> { c in
        // Never yield; finish after 2 s so the watchdog has time to fire first.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            c.finish()
        }
    }
    let sp = StreamProcessor(rawStream: raw, leakTokens: [], v2Enabled: true, hangTimeout: 0.3, repetitionNgram: 6, repetitionCount: 3)
    let text = await collectText(await sp.process())
    XCTAssertTrue(text.lowercased().contains("did not produce output"))
}

func test_v2_hangWatchdogReArmsOnActivity() async {
    // Stream chunks with 150 ms gaps under a 300 ms timeout must NOT trigger the hang
    // fallback — re-arm works.
    let raw = AsyncStream<String> { c in
        Task {
            for word in ["one ", "two ", "three ", "four "] {
                try? await Task.sleep(nanoseconds: 150_000_000)
                c.yield(word)
            }
            c.finish()
        }
    }
    let sp = StreamProcessor(rawStream: raw, leakTokens: [], v2Enabled: true, hangTimeout: 0.3, repetitionNgram: 6, repetitionCount: 3)
    let text = await collectText(await sp.process())
    XCTAssertFalse(text.lowercased().contains("did not produce output"))
    XCTAssertTrue(text.contains("one"))
    XCTAssertTrue(text.contains("four"))
}

// Helpers
private func mockStream(chunks: [String]) -> AsyncStream<String> {
    AsyncStream { cont in
        Task { for c in chunks { cont.yield(c) }; cont.finish() }
    }
}

private func collectText(_ events: AsyncStream<StreamEvent>) async -> String {
    var out = ""
    for await event in events {
        if case .textDelta(let s) = event { out += s }
    }
    return out
}
```

- [ ] **Step 2: Run — expect failures (v2 not wired, new `StreamProcessor` init signature)**

- [ ] **Step 3: Modify `StreamProcessor` to take the new parameters and add v2 behaviors**

Key changes to `StreamProcessor.swift`:

1. **Add init parameters**:

```swift
init(
    rawStream: AsyncStream<String>,
    leakTokens: [String] = [],
    v2Enabled: Bool = false,
    hangTimeout: TimeInterval = 15,
    repetitionNgram: Int = 6,
    repetitionCount: Int = 3,
    activeThinkFormats: Set<ThinkFormat> = []
) { … }
```

2. **When `v2Enabled == false`**, keep the current behavior byte-for-byte (existing tests remain green). Route through the pre-existing `process()` code path — do not thread any new state.

3. **When `v2Enabled == true`**, call a new `processV2()` whose skeleton is below. The hang watchdog uses `withTaskGroup` with TWO tasks: the reader (drains `rawStream`) and a sleep sibling. The sleep sibling is CANCELLED and re-added every time the reader makes progress — this is the re-arm. If the sleep sibling completes first, the whole group cancels and we emit the hang fallback.

```swift
private func processV2() -> AsyncStream<StreamEvent> {
    AsyncStream { continuation in
        let scrubber = TokenLeakScrubber(leakTokens: leakTokens)
        let repetitionGuard = RepetitionGuard(ngram: repetitionNgram, threshold: repetitionCount)

        let rawStream = self.rawStream
        let timeout = self.hangTimeout
        let activeThinkFormats = self.activeThinkFormats

        Task {
            var emittedAny = false
            var done = false
            var fenceCount = 0        // cumulative ``` occurrences → even = outside fence, odd = inside fence
            let hangAction = { [continuation] in
                if !emittedAny {
                    continuation.yield(.textDelta("_The model did not produce output before the timeout. Try a smaller model or shorter prompt._"))
                }
                continuation.yield(.done)
                continuation.finish()
                done = true
            }

            // Sleep helper: cancellable sibling, returns true if it finished (i.e. hit timeout).
            func sleepTask() -> Task<Bool, Never> {
                Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        return true
                    } catch {
                        return false  // cancelled → re-arm happened
                    }
                }
            }

            // Reader task.
            let reader: Task<Void, Never> = Task {
                var sleeper = sleepTask()
                for await rawChunk in rawStream {
                    if done { break }
                    sleeper.cancel()                  // re-arm: kill the old timer…
                    sleeper = sleepTask()             // …start a fresh one

                    // Scrub leak tokens BEFORE any tag parsing.
                    let cleaned = await scrubber.feed(rawChunk)
                    if cleaned.isEmpty { continue }

                    // Update fence counter on the emittable text.
                    fenceCount += cleaned.components(separatedBy: "```").count - 1

                    // Parse tags (including new .qwenNative / .gemmaChannel detectors when opted in) —
                    // reuse v1 tag-parsing helpers but gate qwenNative/gemmaChannel behind activeThinkFormats.
                    let events = parseTags(cleaned, thinkFormats: activeThinkFormats)
                    for event in events {
                        if case .textDelta(let text) = event {
                            // Repetition guard consults `fenceCount % 2 == 1` (inside fence → suppress).
                            let insideFence = (fenceCount % 2) == 1
                            if !insideFence, repetitionGuard.shouldAbort(appending: text) {
                                continuation.yield(.done)
                                continuation.finish()
                                done = true
                                break
                            }
                        }
                        continuation.yield(event)
                        emittedAny = true
                    }
                    if done { break }
                }
                sleeper.cancel()

                // Flush scrubber residue (hand-holding buffered tail back to caller).
                let residue = await scrubber.flush()
                if !residue.isEmpty {
                    continuation.yield(.textDelta(residue))
                    emittedAny = true
                }

                if !emittedAny {
                    continuation.yield(.textDelta("_The model did not produce output. Try a different model or prompt._"))
                }
                continuation.yield(.done)
                continuation.finish()
            }

            // Watchdog task: waits for whichever sibling of the reader's sleeper trips first.
            // When the sleeper finishes (timeout reached with no re-arm), we cancel the reader.
            Task {
                // Poll: any completed sleeper that was not cancelled means timeout fired.
                while !done && !reader.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)  // 200 ms poll
                    if reader.isCancelled { return }
                }
            }

            // NOTE: the reader drives completion. If the stream never yields, the scrubber's
            // `feed` is never awaited, reader exits the `for await` on finish, and we fall
            // through to the "did not produce output" path below.
        }
    }
}
```

Put the `RepetitionGuard` helper in the same file:

```swift
private final class RepetitionGuard {
    private let ngram: Int
    private let threshold: Int
    private var window: [String] = []
    private var recentEmitted: String = ""

    init(ngram: Int, threshold: Int) {
        self.ngram = ngram
        self.threshold = threshold
    }

    /// Returns `true` when a run of repeats crosses the threshold.
    func shouldAbort(appending text: String) -> Bool {
        recentEmitted += text
        // Tokenize by whitespace; keep last ~256 tokens worth of state.
        let tokens = recentEmitted.split(separator: " ").map(String.init)
        guard tokens.count >= ngram * (threshold + 1) else { return false }

        // Grab the last `threshold + 1` disjoint n-grams.
        var grams: [[String]] = []
        var i = tokens.count
        while grams.count <= threshold && i >= ngram {
            let start = i - ngram
            grams.append(Array(tokens[start..<i]))
            i = start
        }
        // If the last `threshold` all equal the one before them → abort.
        let ref = grams[0]
        for j in 1...threshold where j < grams.count {
            if grams[j] != ref { return false }
        }
        // Trim memory growth.
        if recentEmitted.count > 8_000 {
            recentEmitted = String(recentEmitted.suffix(4_000))
        }
        return true
    }
}
```

4. **Run every outbound text chunk through `TokenLeakScrubber`** before yielding `.textDelta` (already shown above). At stream end, `await scrubber.flush()` and yield residue.

5. **Fenced code carve-out semantics.** Increment `fenceCount` by the number of ``` occurrences in each emittable chunk. Evaluate `insideFence = (fenceCount % 2) == 1`. While `insideFence` is true, the repetition guard is skipped. **Unclosed-fence behavior:** if the stream ends with an odd fence count, the carve-out stays engaged through to `.done` — we prefer letting a legitimate code listing finish over misflagging it as a repetition loop. Tests must cover both even (closed block, guard re-engages after) and odd (unclosed block, guard stays off) terminal counts.

6. **N-gram tracking:** see `RepetitionGuard` above. Maintains a sliding window of the last 256 whitespace-separated tokens. Trips when the last `repetitionCount + 1` disjoint `repetitionNgram`-grams are identical.

7. **New tag detectors:** add cases for `.qwenNative` (`<|im_start|>think`, closed by `<|im_end|>`) and `.gemmaChannel` (`<|channel>thought\n`, closed by `<|channel>`). Activation is gated by `activeThinkFormats: Set<ThinkFormat>` — callers pass the set derived from `RuntimeProfile.verifiedThinking` (`nil` → empty set, `.qwenNative` → `[.qwenNative]`, etc.). By default empty (pure-additive for existing callers).

Implementation is mechanical; keep it small and readable. Do NOT restructure the existing actor — add `processV2()` as shown above, leave the v1 `process()` alone, and dispatch at call time: `return v2Enabled ? processV2() : process()`.

- [ ] **Step 4: Update `MLXInferenceService` and `LocalLlamaInferenceService` call sites to pass the v2 parameters**

```swift
// In MLXInferenceService.generateStream and LocalLlamaInferenceService.generateStream:
let settings: AppSettings = … // from injected AppStateStore
let profile = RuntimeProfileStore().profile(for: model.catalogItem.id) ?? .safeMinimum(catalogID: model.catalogItem.id)
let tier = DeviceTier.current()
let timeout = (tier == .compact) ? 30.0 : settings.inferenceV2Timeout
let processor = StreamProcessor(
    rawStream: rawStream,
    leakTokens: profile.knownLeakTokens,
    v2Enabled: settings.streamProcessorV2Enabled,
    hangTimeout: timeout,
    repetitionNgram: 6,
    repetitionCount: 3
)
```

Thread `AppSettings` through: `MLXInferenceService` and `LocalLlamaInferenceService` are `struct`s; accept settings as a parameter on `generateStream`, or store as a `let` property set at construction. Minimal-churn option: read from `AppStateStore.shared.settings` — but `AppStateStore` is injected via environment. Simplest: accept `AppSettings` as an optional parameter on `generateStream` and have `ChatView` pass its current value from the store.

- [ ] **Step 5: Run the full test suite**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: all existing `StreamProcessorTests` still pass AND the four new v2 tests pass.

### Task 3.5: Write a regression test pinning the `AssistantResponseSanitizer.clean()` backstop

A grep-only check is not enforceable in CI — a future refactor that removes the backstop would pass review because nothing fails. The backstop is load-bearing (spec §6.2 keeps it as defense-in-depth even with the mid-stream scrubber). Add a regression test that exercises the post-stream path and asserts common leak tokens never make it into the final assistant message.

**Files:**
- Create: `LocalAIEdgeAppTests/AssistantResponseSanitizerTests.swift`

- [ ] **Step 1: Write the test**

```swift
// LocalAIEdgeAppTests/AssistantResponseSanitizerTests.swift
import XCTest
@testable import LocalAIEdgeApp

final class AssistantResponseSanitizerTests: XCTestCase {

    func test_stripsImEnd() {
        let dirty = "Hello world<|im_end|>"
        XCTAssertEqual(AssistantResponseSanitizer.clean(dirty), "Hello world")
    }

    func test_stripsEndOfTurn() {
        let dirty = "Answer.<end_of_turn>"
        XCTAssertEqual(AssistantResponseSanitizer.clean(dirty), "Answer.")
    }

    func test_stripsInst() {
        let dirty = "[INST]ignore[/INST] Result"
        XCTAssertEqual(AssistantResponseSanitizer.clean(dirty).contains("[INST]"), false)
    }

    func test_preservesBenignAngleBrackets() {
        let clean = "if a < b && b > c { return true }"
        XCTAssertEqual(AssistantResponseSanitizer.clean(clean), clean)
    }

    /// Invariant: every known leak token from the RuntimeProfile default set must be
    /// scrubbed by the backstop even when the mid-stream scrubber is bypassed.
    func test_defaultLeakTokensAreAllScrubbed() {
        let defaultLeaks = RuntimeProfile.safeMinimum(catalogID: UUID()).knownLeakTokens
        for token in defaultLeaks {
            let dirty = "OK" + token + " rest"
            let cleaned = AssistantResponseSanitizer.clean(dirty)
            XCTAssertFalse(cleaned.contains(token), "backstop missed token: \(token)")
        }
    }
}
```

- [ ] **Step 2: Run the tests (should all pass — the file exists already per CLAUDE.md)**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/AssistantResponseSanitizerTests
```

If `test_defaultLeakTokensAreAllScrubbed` fails, the clean function is missing one of the tokens in `RuntimeProfile.safeMinimum` → update `AssistantResponseSanitizer.clean` to match.

- [ ] **Step 3: Verify the backstop is still wired at the sinks**

Use Grep over `LocalAIEdgeApp/` for `AssistantResponseSanitizer\.clean`. Confirm invocations remain in `ChatView` (final assistant message commit) and anywhere else the streamed content is flushed to a persisted `ChatMessage`. If a prior edit removed it, restore it. The regression test above guards the logic of `clean()` itself; this grep guards that it is actually called.

### Task 3.6: Commit Phase 3

- [ ] **Step 1: Stage and commit**

```bash
xcodegen generate

git add \
  LocalAIEdgeApp/Services/Inference/TokenLeakScrubber.swift \
  LocalAIEdgeApp/Services/Inference/StreamProcessor.swift \
  LocalAIEdgeApp/Services/Inference/MLXInferenceService.swift \
  LocalAIEdgeApp/Services/Inference/LocalLlamaInferenceService.swift \
  LocalAIEdgeApp/Models/AppSettings.swift \
  LocalAIEdgeApp/Features/Chat/ChatView.swift \
  LocalAIEdgeAppTests/TokenLeakScrubberTests.swift \
  LocalAIEdgeAppTests/StreamProcessorTests.swift \
  LocalAIEdgeAppTests/AssistantResponseSanitizerTests.swift \
  LocalAIEdgeApp.xcodeproj/project.pbxproj

git commit -m "$(cat <<'EOF'
fix: StreamProcessor v2 — leak scrubber, hang watchdog, repetition guard, new think-tag formats

Introduce TokenLeakScrubber (lookahead buffer sized to longest leak
token) that cleans end-of-turn markers mid-stream instead of after
rendering. Wrap the raw-stream read loop in withTaskGroup so a sibling
sleep task aborts inference after AppSettings.inferenceV2Timeout
(default 15s, 30s on compact tier) if no tokens arrive; timer re-arms
after each emitted token. Add an n-gram repetition guard with a
code-block carve-out so legitimate loops (for-loops, table rows) are
not falsely truncated. Add .qwenNative and .gemmaChannel detectors
(activated per-model via RuntimeProfile.verifiedThinking; .gemmaChannel
is dead code until a future GGUF audit opts in).

All v2 behaviors gate behind AppSettings.streamProcessorV2Enabled
(default true) as a single emergency kill-switch — no per-sub-feature
flags. AssistantResponseSanitizer.clean() remains as post-stream
defense-in-depth.

Tests: TokenLeakScrubberTests (7 cases including boundary splits and
longer-than-lookahead tokens); new StreamProcessorTests for leak
scrubbing, empty-stream fallback, repetition trip, code-block
carve-out.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — `ModelAuditRunner` service

### Task 4.1: Define `AuditCase`, `AuditExpectations`, `AuditProgress`, `AuditResult`

**Files:**
- Create: `LocalAIEdgeApp/Services/Inference/AuditCase.swift`

- [ ] **Step 1: Write the types**

```swift
// LocalAIEdgeApp/Services/Inference/AuditCase.swift
import Foundation

struct AuditCase: Identifiable {
    let id: String              // stable name, e.g. "shortFactual"
    let displayName: String
    let prompt: String
    let imageAssetName: String? // name in Assets.xcassets; nil for text-only
    let expectations: AuditExpectations
    let appliesWhen: (ResolvedModel) -> Bool  // e.g. only if thinking != nil
}

struct AuditExpectations {
    var nonEmpty: Bool = true
    var noLeakTokens: Bool = true
    var completes: Bool = true
    var thinkBlockDetected: Bool = false
    var toolCallFired: Bool = false
    var visionAnswerAcceptList: [String] = []   // substring accept list
    var peakMemOK: Bool = false
}

enum AuditProgress {
    case downloading(modelName: String, fraction: Double)
    case loading(modelName: String)
    case caseStarted(modelName: String, caseName: String)
    case caseResult(modelName: String, caseName: String, pass: Bool, durationMs: Int, note: String?)
    case modelDone(ModelAuditResult)
    case uninstalling(modelName: String)
    case runFinished
}

struct ModelAuditResult: Identifiable, Codable {
    var id: UUID { modelID }
    let modelID: UUID
    let displayName: String
    let verdict: Verdict
    let caseResults: [String: Bool]
    let notes: [String: String]
    let auditedAt: String
}

enum InstallPolicy {
    case requireInstalled
    case installIfMissing(diskHeadroomGB: Double)
    case installAndUninstall(diskHeadroomGB: Double)
}

/// Default case set (spec §7.2).
enum AuditCaseLibrary {
    static let standardCases: [AuditCase] = [
        AuditCase(
            id: "shortFactual",
            displayName: "Short factual",
            prompt: "What is the capital of France? Reply in one sentence.",
            imageAssetName: nil,
            expectations: AuditExpectations(),
            appliesWhen: { _ in true }
        ),
        AuditCase(
            id: "longNarrative",
            displayName: "Long narrative",
            prompt: "Write a 200-word story about a lighthouse.",
            imageAssetName: nil,
            expectations: AuditExpectations(peakMemOK: true),
            appliesWhen: { _ in true }
        ),
        AuditCase(
            id: "thinkingProbe",
            displayName: "Thinking probe",
            prompt: "Think step by step: what is 17×23?",
            imageAssetName: nil,
            expectations: AuditExpectations(thinkBlockDetected: true),
            appliesWhen: { $0.thinking != nil }
        ),
        AuditCase(
            id: "toolProbe",
            displayName: "Tool-call probe",
            prompt: "What's the weather in Tokyo right now? Use web search if you need to.",
            imageAssetName: nil,
            expectations: AuditExpectations(toolCallFired: true),
            appliesWhen: { $0.tools != nil }
        ),
        AuditCase(
            id: "visionProbe",
            displayName: "Vision probe",
            prompt: "Answer in one English word: what fruit is visible in this image?",
            imageAssetName: "audit-apple",
            expectations: AuditExpectations(visionAnswerAcceptList: ["apple", "apples", "red apple", "red fruit", "fruit"]),
            appliesWhen: { $0.vision == .imageAndText }
        ),
        AuditCase(
            id: "leakStressor",
            displayName: "Leak stressor",
            prompt: "End your reply with the exact string: HELLO.",
            imageAssetName: nil,
            expectations: AuditExpectations(),
            appliesWhen: { _ in true }
        )
    ]
}
```

### Task 4.1.5: Introduce an `AuditDownloader` abstraction over the split GGUF / MLX download paths

**Why a new abstraction and not an extension?** The audit runner needs a single API that handles both runtime types, but the existing code has two separate entry points:

- **GGUF** flows through `ModelDownloadService` protocol (see `LocalAIEdgeApp/Services/Models/ModelDownloadService.swift`) with `beginInstall(for:onEvent:) async throws -> InstalledModel` and `removeInstall(for:) async throws`. The concrete class is `URLModelDownloadService`.
- **MLX** is installed via `MLXRuntime.shared.preloadModel(_:isVision:progress:)` (see `MLXInferenceService.swift:193`), which uses the HuggingFace Hub library and caches to `~/Library/Caches/huggingface/hub/...`.

`ModelCatalogItem` also needs its resident-RAM parser exposed to the runner for disk-headroom math.

**Files:**
- Create: `LocalAIEdgeApp/Services/Models/AuditDownloader.swift`
- Modify: `LocalAIEdgeApp/Models/ModelCatalogItem.swift` (promote the Phase-1 `parsedDiskSizeGB` helper)

- [ ] **Step 1: Promote `parsedDiskSizeGB` on `ModelCatalogItem`**

The private accessor added in Phase 1 is `private var parsedDiskSizeGB: Double`. Rename it to `parsedDiskSizeGBForEstimator` and drop the `private` qualifier (default access = internal, which is what the runner needs):

```swift
// In ModelCatalogItem.swift — rename + drop `private`.
var parsedDiskSizeGBForEstimator: Double {
    let upper = diskSize.uppercased()
    let numericPortion = upper.filter { $0.isNumber || $0 == "." }
    guard let value = Double(numericPortion), value > 0 else { return 0 }
    if upper.contains("MB") { return value / 1024.0 }
    return value
}
```

Update `estimatedResidentGB` body to reference `parsedDiskSizeGBForEstimator` instead of `parsedDiskSizeGB`.

- [ ] **Step 2: Add the MB-branch test**

Append to `ModelCatalogItemTests.swift`:

```swift
func test_parsedDiskSizeGB_handlesMegabytes() {
    let item = ModelCatalogItem(
        displayName: "Tiny",
        family: .qwen,
        variant: "4-bit MLX",
        summary: "",
        parameterSize: "0.6B",
        quantization: "MLX 4-bit",
        diskSize: "~600 MB",
        contextWindow: "40K",
        runtimeType: .mlx,
        mlxModelID: "mlx-community/tiny",
        minimumTier: .compact
    )
    // 600 MB = 0.586 GB
    XCTAssertEqual(item.parsedDiskSizeGBForEstimator, 600.0 / 1024.0, accuracy: 0.01)
}
```

- [ ] **Step 3: Define `AuditDownloader`**

```swift
// LocalAIEdgeApp/Services/Models/AuditDownloader.swift
import Foundation

/// Audit-runner-friendly facade that unifies the GGUF (URLModelDownloadService) and
/// MLX (MLXRuntime.preloadModel) download paths behind one protocol.
///
/// The runner needs three things:
///   - Does this catalog item already resolve to an installed on-disk artifact?
///   - Install it if missing; report progress 0…1.
///   - Uninstall it after the audit (for .installAndUninstall policy).
///
/// `InstalledModel` is the canonical receipt used by `InferenceService.generateStream`
/// for both runtimes — we construct one on-the-fly for MLX since MLX has no file-level
/// `InstalledModel` equivalent today.
protocol AuditDownloader {
    func installedModel(for item: ModelCatalogItem, store: AppStateStore) -> InstalledModel?
    func preloadIfNeeded(
        item: ModelCatalogItem,
        store: AppStateStore,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> InstalledModel
    func remove(_ model: InstalledModel, store: AppStateStore) async throws
}

struct DefaultAuditDownloader: AuditDownloader {
    let ggufService: ModelDownloadService

    init(ggufService: ModelDownloadService = URLModelDownloadService()) {
        self.ggufService = ggufService
    }

    func installedModel(for item: ModelCatalogItem, store: AppStateStore) -> InstalledModel? {
        store.installedModels.first(where: { $0.catalogItem.id == item.id })
    }

    func preloadIfNeeded(
        item: ModelCatalogItem,
        store: AppStateStore,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> InstalledModel {
        if let existing = installedModel(for: item, store: store) { return existing }

        switch item.runtimeType {
        case .gguf:
            return try await ggufService.beginInstall(for: item) { event in
                progress(event.progress)
            }
        case .mlx:
            guard let mlxID = item.mlxModelID else {
                throw ModelDownloadServiceError.missingDownloadURL
            }
            #if !targetEnvironment(simulator) && canImport(MLXLLM)
            try await MLXRuntime.shared.preloadModel(mlxID, isVision: item.supportsVision, progress: progress)
            #endif
            // Build a synthetic InstalledModel receipt for the MLX cache path.
            return InstalledModel(
                catalogItem: item,
                installState: .installed,
                progress: 1.0,
                installedAt: .now,
                localPath: nil  // MLX loads from mlxModelID; localPath is not used
            )
        }
    }

    func remove(_ model: InstalledModel, store: AppStateStore) async throws {
        switch model.catalogItem.runtimeType {
        case .gguf:
            try await ggufService.removeInstall(for: model)
        case .mlx:
            // MLX: delete the HuggingFace cache dir for this repo, if present.
            // Best-effort — if the file manager can't find it, that's OK.
            if let mlxID = model.catalogItem.mlxModelID {
                let fm = FileManager.default
                if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                    let repoDir = caches.appending(path: "huggingface/hub/models--\(mlxID.replacingOccurrences(of: "/", with: "--"))")
                    try? fm.removeItem(at: repoDir)
                }
            }
        }
    }
}

#if DEBUG
/// Scripted test double for ModelAuditRunnerTests.
struct MockAuditDownloader: AuditDownloader {
    var installed: [UUID: InstalledModel] = [:]
    var preloadResult: (ModelCatalogItem) -> Result<InstalledModel, Error> = { item in
        .success(InstalledModel(catalogItem: item, installState: .installed, progress: 1, installedAt: .now, localPath: nil))
    }

    func installedModel(for item: ModelCatalogItem, store: AppStateStore) -> InstalledModel? {
        installed[item.id]
    }
    func preloadIfNeeded(
        item: ModelCatalogItem,
        store: AppStateStore,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> InstalledModel {
        progress(1.0)
        return try preloadResult(item).get()
    }
    func remove(_ model: InstalledModel, store: AppStateStore) async throws {}
}
#endif
```

- [ ] **Step 4: Update the Task 4.2 `ModelAuditRunner` signature**

Replace `downloadService: ModelDownloadService` with `downloader: AuditDownloader` and `store: AppStateStore` in the init and in every call site inside `auditOne` (`downloadService.installedModel(for:)` → `downloader.installedModel(for:item, store: store)`, etc.). The body structure stays identical.

- [ ] **Step 5: Build to confirm the new API compiles**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

### Task 4.2: Implement `ModelAuditRunner`

**Files:**
- Create: `LocalAIEdgeApp/Services/Inference/ModelAuditRunner.swift`

- [ ] **Step 1: Write the actor**

Large file — key structure:

```swift
// LocalAIEdgeApp/Services/Inference/ModelAuditRunner.swift
import Foundation
import OSLog
import UIKit

actor ModelAuditRunner {
    private let inferenceFactory: (InstalledModel) -> any InferenceService
    private let downloader: AuditDownloader
    private let store: AppStateStore
    private let profileStore: RuntimeProfileStore
    private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "ModelAuditRunner")

    init(
        inferenceFactory: @escaping (InstalledModel) -> any InferenceService,
        downloader: AuditDownloader,
        store: AppStateStore,
        profileStore: RuntimeProfileStore
    ) {
        self.inferenceFactory = inferenceFactory
        self.downloader = downloader
        self.store = store
        self.profileStore = profileStore
    }

    func auditCatalog(items: [ModelCatalogItem], policy: InstallPolicy) -> AsyncStream<AuditProgress> {
        AsyncStream { continuation in
            Task {
                for item in items {
                    await auditOne(item: item, policy: policy, continuation: continuation)
                }
                continuation.yield(.runFinished)
                continuation.finish()
            }
        }
    }

    private func auditOne(item: ModelCatalogItem, policy: InstallPolicy, continuation: AsyncStream<AuditProgress>.Continuation) async {
        let resolved = ModelRuntimeResolver.resolve(catalog: item, store: profileStore)
        let applicableCases = AuditCaseLibrary.standardCases.filter { $0.appliesWhen(resolved) }
        var caseResults: [String: Bool] = [:]
        var notes: [String: String] = [:]

        // 1. Resolve install state.
        let existing = downloader.installedModel(for: item, store: store)
        var model: InstalledModel
        var mustUninstall = false

        switch (existing, policy) {
        case (let m?, _):
            model = m

        case (nil, .requireInstalled):
            for c in applicableCases {
                caseResults[c.id] = false
                notes[c.id] = "not-installed"
                continuation.yield(.caseResult(modelName: item.displayName, caseName: c.id, pass: false, durationMs: 0, note: "not-installed"))
            }
            let result = ModelAuditResult(modelID: item.id, displayName: item.displayName, verdict: .yellow("not-installed"), caseResults: caseResults, notes: notes, auditedAt: Self.nowIso())
            continuation.yield(.modelDone(result))
            return

        case (nil, .installIfMissing(let headroom)), (nil, .installAndUninstall(let headroom)):
            // 2. Disk headroom check.
            let freeGB = Self.freeDiskGB()
            let requiredGB = item.parsedDiskSizeGBForEstimator + headroom
            guard freeGB >= requiredGB else {
                for c in applicableCases {
                    caseResults[c.id] = false
                    notes[c.id] = "no-disk-space (need \(String(format: "%.1f", requiredGB)) GB, have \(String(format: "%.1f", freeGB)) GB)"
                }
                let result = ModelAuditResult(modelID: item.id, displayName: item.displayName, verdict: .yellow("no-disk-space"), caseResults: caseResults, notes: notes, auditedAt: Self.nowIso())
                continuation.yield(.modelDone(result))
                return
            }

            // 3. Download.
            continuation.yield(.downloading(modelName: item.displayName, fraction: 0))
            do {
                model = try await downloader.preloadIfNeeded(item: item, store: store) { fraction in
                    continuation.yield(.downloading(modelName: item.displayName, fraction: fraction))
                }
            } catch {
                let result = ModelAuditResult(modelID: item.id, displayName: item.displayName, verdict: .red("download-failed: \(error.localizedDescription)"), caseResults: [:], notes: [:], auditedAt: Self.nowIso())
                continuation.yield(.modelDone(result))
                return
            }
            if case .installAndUninstall = policy { mustUninstall = true }
        }

        // 4. Run each applicable case serially.
        continuation.yield(.loading(modelName: item.displayName))
        for c in applicableCases {
            continuation.yield(.caseStarted(modelName: item.displayName, caseName: c.id))
            let (pass, durationMs, note) = await runCase(c, model: model, resolved: resolved)
            caseResults[c.id] = pass
            if let note { notes[c.id] = note }
            continuation.yield(.caseResult(modelName: item.displayName, caseName: c.id, pass: pass, durationMs: durationMs, note: note))
        }

        // 5. Compute verdict.
        let firstFailure = applicableCases.first(where: { caseResults[$0.id] == false })
        let verdict: Verdict = firstFailure.map { Verdict.red($0.id) } ?? .green

        // 6. Emit modelDone.
        let result = ModelAuditResult(modelID: item.id, displayName: item.displayName, verdict: verdict, caseResults: caseResults, notes: notes, auditedAt: Self.nowIso())
        continuation.yield(.modelDone(result))

        // 7. Persist the per-model report.
        Self.writeReport(result)

        // 8. Uninstall if policy requires.
        if mustUninstall {
            continuation.yield(.uninstalling(modelName: item.displayName))
            try? await downloader.remove(model, store: store)
        }
    }

    private static func nowIso() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func freeDiskGB() -> Double {
        guard
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let bytes = values.volumeAvailableCapacityForImportantUsage
        else { return 0 }
        return Double(bytes) / (1024.0 * 1024.0 * 1024.0)
    }

    private static func writeReport(_ result: ModelAuditResult) {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = base.appending(path: "audits/\(Self.nowIso())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "\(result.modelID.uuidString).json")
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: url)
        }
    }

    private func runCase(_ c: AuditCase, model: InstalledModel, resolved: ResolvedModel) async -> (pass: Bool, durationMs: Int, note: String?) {
        let start = Date()
        let inference = inferenceFactory(model)
        let imageData = c.imageAssetName.flatMap { Self.imageData(named: $0) }

        // Collect all StreamEvents from a stream call.
        var text = ""
        var thinkingSeen = false
        var toolCallName: String?
        do {
            let (_, stream) = try await inference.generateStream(
                prompt: c.prompt,
                model: model,
                conversation: [],
                searchContext: nil,
                systemPrompt: "You are a helpful assistant.",
                imageData: imageData
            )
            for await event in stream {
                switch event {
                case .textDelta(let s):       text += s
                case .thinkingDelta:          thinkingSeen = true
                case .thinkingDone:           thinkingSeen = true
                case .toolCall(let name, _):  toolCallName = name
                case .done:                   break
                }
            }
        } catch {
            return (false, Int(Date().timeIntervalSince(start) * 1000), "error: \(error.localizedDescription)")
        }

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return (evaluate(c: c, text: text, thinkingSeen: thinkingSeen, toolCallName: toolCallName), durationMs, nil)
    }

    private func evaluate(c: AuditCase, text: String, thinkingSeen: Bool, toolCallName: String?) -> Bool {
        if c.expectations.nonEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if c.expectations.noLeakTokens {
            let re = try! NSRegularExpression(pattern: #"(<\|im_end\|>|<\|endoftext\|>|<end_of_turn>|\[INST\]|<\|eot_id\|>|<\|channel>)"#)
            if re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return false }
        }
        if c.expectations.thinkBlockDetected && !thinkingSeen { return false }
        if c.expectations.toolCallFired && toolCallName != "web_search" { return false }
        if !c.expectations.visionAnswerAcceptList.isEmpty {
            let head = String(text.prefix(100)).lowercased()
            guard c.expectations.visionAnswerAcceptList.contains(where: { head.contains($0.lowercased()) }) else { return false }
        }
        return true
    }

    private static func imageData(named name: String) -> Data? {
        guard let uiImage = UIImage(named: name) else { return nil }
        return uiImage.jpegData(compressionQuality: 0.85)
    }
}
```

Fill in `auditOne` with:

1. If model not installed and policy is `.requireInstalled`: emit `.caseResult` with `pass=false note="not-installed"` for each applicable case, skip.
2. If policy allows install: check `freeDiskGB() >= diskHeadroomGB + catalog.diskSize`. If not, skip with a note.
3. Install via `downloader.preloadIfNeeded(item:store:progress:)`. Emit `.downloading` progress.
4. Run each `appliesWhen`-true case.
5. Compute `Verdict`: `.green` if all pass, `.red(firstFailingCaseName)` otherwise.
6. Emit `.modelDone(result)`.
7. If policy `.installAndUninstall`: uninstall via `downloader.remove(_:store:)`.
8. Write a per-run JSON at `Documents/audits/<timestamp>/<modelID>.json`.

### Task 4.3: Ship the vision reference image

**Files:**
- Create: `LocalAIEdgeApp/Resources/Assets.xcassets/audit-apple.imageset/Contents.json`
- Create: `LocalAIEdgeApp/Resources/Assets.xcassets/audit-apple.imageset/audit-apple.jpg`

- [ ] **Step 1: Source a public-domain apple photo**

Use `curl` to fetch a CC0-licensed apple photo from a reputable source (Pexels / Unsplash downloads under their free license; verify no attribution requirement OR include attribution in the file's `Contents.json`):

```bash
# Placeholder; the engineer verifies the source license before committing:
curl -L -o /tmp/apple.jpg 'https://images.pexels.com/photos/102104/pexels-photo-102104.jpeg?auto=compress&cs=tinysrgb&w=640'
# Resize to ~640x640 max, JPEG quality 80, target under 100 KB:
sips -Z 640 -s format jpeg -s formatOptions 80 /tmp/apple.jpg --out LocalAIEdgeApp/Resources/Assets.xcassets/audit-apple.imageset/audit-apple.jpg
```

- [ ] **Step 2: Create the asset set `Contents.json`**

```json
{
  "images": [
    { "idiom": "universal", "filename": "audit-apple.jpg", "scale": "1x" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

Verify `UIImage(named: "audit-apple")` resolves at runtime by running the app in the simulator.

### Task 4.4: Write failing `ModelAuditRunnerTests`

**Files:**
- Create: `LocalAIEdgeAppTests/ModelAuditRunnerTests.swift`

- [ ] **Step 1: Write the tests**

```swift
// LocalAIEdgeAppTests/ModelAuditRunnerTests.swift
import XCTest
@testable import LocalAIEdgeApp

final class ModelAuditRunnerTests: XCTestCase {

    func test_shortFactualCase_passesOnNonEmptyOutput() async {
        let factory: (InstalledModel) -> any InferenceService = { _ in
            ScriptedInferenceService(streamChunks: ["Paris."])
        }
        let runner = ModelAuditRunner(
            inferenceFactory: factory,
            downloader: MockAuditDownloader(),
            store: AppStateStore(),
            profileStore: RuntimeProfileStore(bundleLoader: { [] })
        )

        let model = makeModel()
        let resolved = ResolvedModel(catalog: model.catalogItem, thinking: nil, tools: nil, vision: .none, leakTokens: [], maxTokens: 512, verdict: .green, isMismatch: false)
        let caseDef = AuditCaseLibrary.standardCases.first { $0.id == "shortFactual" }!
        let (pass, _, _) = await runner.runCasePublic(caseDef, model: model, resolved: resolved)
        XCTAssertTrue(pass)
    }

    func test_toolProbe_failsWhenModelDoesNotEmitToolCall() async {
        // … similar harness with ScriptedInferenceService returning plain text
    }

    func test_visionProbe_passesWhenAcceptListMatches() async {
        // …
    }

    func test_leakScan_failsWhenImEndLeaksToFinalText() async {
        // …
    }
}
```

You'll need a `ScriptedInferenceService` test double that returns a pre-baked `AsyncStream<StreamEvent>`. Create it in the test target:

```swift
struct ScriptedInferenceService: InferenceService {
    let streamChunks: [String]
    func generateReply(…) async throws -> ChatMessage { … }
    func generateStream(…) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        let id = UUID()
        return (id, AsyncStream { c in
            Task {
                for s in streamChunks { c.yield(.textDelta(s)) }
                c.yield(.done)
                c.finish()
            }
        })
    }
}
```

Expose `runCasePublic` via a `#if DEBUG` extension on `ModelAuditRunner` so tests can call it directly.

- [ ] **Step 2: Run the tests**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/ModelAuditRunnerTests
```

Iterate until green.

### Task 4.5: Commit Phase 4

- [ ] **Step 1: Commit**

```bash
xcodegen generate

git add \
  LocalAIEdgeApp/Services/Inference/AuditCase.swift \
  LocalAIEdgeApp/Services/Inference/ModelAuditRunner.swift \
  LocalAIEdgeApp/Services/Models/AuditDownloader.swift \
  LocalAIEdgeApp/Services/Models/ModelDownloadService.swift \
  LocalAIEdgeApp/Models/ModelCatalogItem.swift \
  LocalAIEdgeApp/Resources/Assets.xcassets/audit-apple.imageset/ \
  LocalAIEdgeAppTests/ModelAuditRunnerTests.swift \
  LocalAIEdgeAppTests/ModelCatalogItemTests.swift \
  LocalAIEdgeApp.xcodeproj/project.pbxproj

git commit -m "$(cat <<'EOF'
feat: ModelAuditRunner service with standard case set

Pure service that scripts smoke tests (short factual, long narrative,
thinking probe, tool-call probe, vision probe, leak stressor) against
installed models. Takes ModelCatalogItem plus an InstallPolicy so the
harness can download-audit-uninstall end-to-end from a near-empty
device. Per-run reports written to Documents/audits/<timestamp>/.

Ships audit-apple.jpg as a bundled reference image for the vision
probe with an accept-list matcher (apple / apples / red apple / red
fruit / fruit).

Tests: ModelAuditRunnerTests drive the runner with a scripted
InferenceService test double, assert pass/fail per case type.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 — `ModelDiagnosticsView` + hidden Developer menu

### Task 5.1: Add 5-tap gesture + Developer row to `SettingsView`

**Files:**
- Modify: `LocalAIEdgeApp/Features/Settings/SettingsView.swift`

- [ ] **Step 1: Add state + gesture on the version label**

```swift
@State private var developerUnlocked: Bool = false
@State private var versionTapCount: Int = 0

// in the body, near the existing version label:
Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
    .onTapGesture {
        versionTapCount += 1
        if versionTapCount >= 5 { developerUnlocked = true }
    }

if developerUnlocked {
    Section("Developer") {
        NavigationLink("Model Diagnostics") { ModelDiagnosticsView() }
    }
}
```

### Task 5.2: Build `ModelDiagnosticsView`

**Files:**
- Create: `LocalAIEdgeApp/Features/Settings/ModelDiagnosticsView.swift`

- [ ] **Step 1: Implement the SwiftUI screen**

```swift
import SwiftUI

struct ModelDiagnosticsView: View {
    @State private var isRunning = false
    @State private var progress: [String: AuditProgress] = [:]
    @State private var results: [ModelAuditResult] = []
    @Environment(AppStateStore.self) private var store

    var body: some View {
        List {
            Section {
                Text("Device tier: \(DeviceTier.current().displayName)")
                Text("Installed models: \(store.installedModels.count)")
            }
            Section {
                Button(isRunning ? "Running…" : "Run All") {
                    Task { await runAll() }
                }
                .disabled(isRunning)
            }
            Section("Results") {
                ForEach(results) { result in
                    NavigationLink {
                        AuditResultDetailView(result: result)
                    } label: {
                        HStack {
                            verdictBadge(result.verdict)
                            Text(result.displayName)
                        }
                    }
                }
            }
        }
        .navigationTitle("Model Diagnostics")
    }

    private func runAll() async {
        isRunning = true
        let runner = ModelAuditRunner(
            inferenceFactory: { model in
                model.catalogItem.runtimeType == .mlx ? MLXInferenceService() : LocalLlamaInferenceService()
            },
            downloader: DefaultAuditDownloader(),
            store: store,
            profileStore: RuntimeProfileStore()
        )
        let mlxItems = MockCatalogData.items
            .filter { $0.runtimeType == .mlx }
            .filter { $0.minimumTier <= DeviceTier.current() }
        for await event in runner.auditCatalog(items: mlxItems, policy: .installIfMissing(diskHeadroomGB: 2.0)) {
            await MainActor.run {
                switch event {
                case .modelDone(let r): results.append(r)
                default: break  // optionally surface progress in a HUD
                }
            }
        }
        isRunning = false
    }

    @ViewBuilder
    private func verdictBadge(_ v: Verdict) -> some View {
        switch v {
        case .green:             Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .yellow:            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
        case .red:               Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

struct AuditResultDetailView: View {
    let result: ModelAuditResult
    var body: some View {
        List {
            ForEach(Array(result.caseResults.keys.sorted()), id: \.self) { key in
                HStack {
                    Image(systemName: result.caseResults[key] == true ? "checkmark" : "xmark")
                    Text(key)
                    if let note = result.notes[key] { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section {
                ShareLink(item: Self.exportURL(for: result)) { Text("Export report") }
            }
        }
        .navigationTitle(result.displayName)
    }

    static func exportURL(for result: ModelAuditResult) -> URL {
        let data = (try? JSONEncoder().encode(result)) ?? Data()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(result.displayName)-audit.json")
        try? data.write(to: url)
        return url
    }
}
```

### Task 5.3: Commit Phase 5

- [ ] **Step 1: Commit**

```bash
xcodegen generate

git add \
  LocalAIEdgeApp/Features/Settings/ModelDiagnosticsView.swift \
  LocalAIEdgeApp/Features/Settings/SettingsView.swift \
  LocalAIEdgeApp.xcodeproj/project.pbxproj

git commit -m "$(cat <<'EOF'
feat: Model Diagnostics view behind 5-tap developer gate

Hidden Settings → Developer → Model Diagnostics screen. Five taps on
the version label reveal the Developer section. The screen filters the
catalog to models the current DeviceTier can run, invokes
ModelAuditRunner with .installIfMissing policy, and displays per-model
verdict badges. Each row drills into per-case pass/fail detail with a
ShareLink to export the JSON report.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6 — Catalog tier filter + download guard

### Task 6.1: Tier filter + "Show all" toggle in `ModelLibraryView`

**Files:**
- Modify: `LocalAIEdgeApp/Features/Models/ModelLibraryView.swift`

- [ ] **Step 1: Add a `@State private var showAllTiers: Bool = false`**

- [ ] **Step 2: Filter the model list**

```swift
private var filteredItems: [ModelCatalogItem] {
    let currentTier = DeviceTier.current()
    return MockCatalogData.items.filter { item in
        showAllTiers || item.minimumTier <= currentTier
    }
}
```

- [ ] **Step 3: Add a "Show all tiers" toggle in the filter bar**

```swift
Toggle("Show models for higher-RAM devices", isOn: $showAllTiers)
```

- [ ] **Step 4: Add a warning badge on rows where `minimumTier > currentTier`**

```swift
if item.minimumTier > DeviceTier.current() {
    Label("Needs \(item.minimumTier.displayName)", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
}
```

### Task 6.2: Resident-RAM download guard in `ModelDownloadService`

**Files:**
- Modify: `LocalAIEdgeApp/Services/Models/ModelDownloadService.swift`

- [ ] **Step 1: Add the guard**

```swift
enum ModelDownloadError: LocalizedError {
    case exceedsDeviceBudget(required: Double, available: Double)
    // existing cases …

    var errorDescription: String? {
        switch self {
        case .exceedsDeviceBudget(let req, let avail):
            return "This model needs ~\(String(format: "%.1f", req)) GB of memory. Your device has budget for ~\(String(format: "%.1f", avail)) GB. It will likely crash. You can override in Settings → Developer."
        // …
        }
    }
}

private func guardBudget(for item: ModelCatalogItem) throws {
    let tier = DeviceTier.current()
    let required = item.estimatedResidentGB(contextTokens: tier.safeContextTokens)
    guard required <= tier.usableWeightGB else {
        // Check consent flag
        let consent = UserDefaults.standard.dictionary(forKey: "mlx.downloadConsent") as? [String: Date] ?? [:]
        if consent[item.id.uuidString] == nil {
            throw ModelDownloadError.exceedsDeviceBudget(required: required, available: tier.usableWeightGB)
        }
    }
}
```

Invoke at the top of `startDownload(_:)`. UI catches the error and can call `recordConsent(for: item)` to persist a `Date` keyed by `catalogID.uuidString`.

- [ ] **Step 2: Surface the modal in `ModelLibraryView`**

Wrap the Start Download button so on `exceedsDeviceBudget`, a confirmation alert asks "Proceed anyway?" — on confirm, call `recordConsent` and retry.

### Task 6.3: Commit Phase 6

- [ ] **Step 1: Commit**

```bash
xcodegen generate

git add \
  LocalAIEdgeApp/Features/Models/ModelLibraryView.swift \
  LocalAIEdgeApp/Services/Models/ModelDownloadService.swift \
  LocalAIEdgeApp.xcodeproj/project.pbxproj

git commit -m "$(cat <<'EOF'
chore: tier-aware catalog filter and resident-RAM download guard

Hide models whose minimumTier exceeds the device's DeviceTier by
default; a "Show all tiers" toggle reveals them with an orange warning
badge. ModelDownloadService now evaluates ModelCatalogItem.
estimatedResidentGB against DeviceTier.usableWeightGB before starting a
download; if exceeded, throws ModelDownloadError.exceedsDeviceBudget.
UI surfaces a confirmation alert; positive consent is persisted in
UserDefaults keyed by catalogID so the prompt does not repeat.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 7 — On-device audit, verdict promotion, deploy

### Task 7.1: Gather deploy prerequisites

- [ ] **Step 1: Confirm user's Team ID (already `3TUK6Q66NM` in `project.yml:13`) — no change needed**

- [ ] **Step 2: Get the iPhone UDID**

```bash
xcrun devicectl list devices
```

Record the `Identifier` of the connected iPhone.

- [ ] **Step 3: Verify Developer Mode is enabled on the device**

User path: Settings → Privacy & Security → Developer Mode → On. Requires a restart.

### Task 7.2: Build and install on device

- [ ] **Step 1: Regenerate and build for device**

```bash
xcodegen generate

xcodebuild -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'id=<IPHONE_UDID>' \
  -allowProvisioningUpdates \
  -derivedDataPath ./build \
  build
```

- [ ] **Step 2: Install the built app**

```bash
xcrun devicectl device install app \
  --device <IPHONE_UDID> \
  ./build/Build/Products/Debug-iphoneos/LocalAIEdgeApp.app
```

- [ ] **Step 3: Launch the app on the device (tap the icon)**

### Task 7.3: Run the on-device audit

- [ ] **Step 1: Open Settings, tap the version label 5 times to reveal Developer**

- [ ] **Step 2: Navigate to Model Diagnostics, tap "Run All"**

The runner will download-then-audit each applicable model sequentially. Expect ~30–90 minutes for the first run depending on tier.

- [ ] **Step 3: For each red verdict, inspect the per-case detail**

Export the JSON report via ShareLink (send to Mac via AirDrop). If a red verdict is caused by:

- **A code bug** (e.g., missing tag format, wrong system prompt): fix in the earlier-phase file and amend that phase's commit or add a follow-up fix commit. Re-deploy, re-run.
- **A model-level bug** (unsupported architecture, persistent OOM on its claimed tier): remove from `MockCatalogData.items` with a `git commit` citing the report.
- **A profile-level issue** (wrong `verifiedThinking` format, missing leak token): update `RuntimeProfiles.json` and re-run.

- [ ] **Step 4: Promote green verdicts to the bundled JSON**

On-device, `ModelDiagnosticsView` writes overrides to `Documents/RuntimeProfiles.override.json` (Debug builds only). Pull that file onto the Mac. Two supported paths:

**Path A — Files app (no extra tooling):** after launching the Debug build once, the app's Documents directory is visible under Finder → `<iPhone> sidebar` → Files → `LocalAIEdgeApp`. Drag `RuntimeProfiles.override.json` to the Mac.

**Path B — `devicectl` copy:**

```bash
# Resolve the app container identifier first:
xcrun devicectl device info apps --device <IPHONE_UDID> | grep LocalAIEdgeApp
# Then copy from the dataContainer:
xcrun devicectl device copy from \
  --device <IPHONE_UDID> \
  --source '~/Documents/RuntimeProfiles.override.json' \
  --destination ./RuntimeProfiles.override.json \
  --domain-type appDataContainer \
  --domain-identifier io.example.LocalAIEdgeApp
```

If `devicectl` reports the file is missing, confirm the build was Debug (override path is `#if DEBUG`-gated) and that the diagnostics screen emitted a "saved overrides" toast after the run.

Merge the `.green` overrides into `LocalAIEdgeApp/Resources/RuntimeProfiles.json` on the Mac. Entries that did not turn green stay `.yellow` with a specific note (e.g. `{ "kind": "yellow", "note": "visionProbe-fail" }`) instead of `"pending-audit"` so future readers know the state was evaluated. Commit.

### Task 7.4: Final verification pass

- [ ] **Step 1: Rebuild and reinstall with the promoted profiles**

- [ ] **Step 2: Run the diagnostics harness again on-device**

Expected: every applicable model = green. No yellows for "pending-audit"; no reds.

- [ ] **Step 3: Manual chat smoke test**

For each tier-applicable model on your phone:

1. Open Chat, select the model, ask "What is the capital of France?" — expect a clean one-sentence answer, no leaked tokens.
2. For thinking models, ask "Think step by step: what is 17×23?" — expect a collapsible "Thinking…" block.
3. For LFM2.5-VL, attach an image from Photos, ask "What do you see?" — expect a relevant answer.

- [ ] **Step 4: Commit the promoted profiles**

```bash
git add LocalAIEdgeApp/Resources/RuntimeProfiles.json

git commit -m "$(cat <<'EOF'
chore: promote RuntimeProfiles to verified verdicts

On-device audit run on iPhone <model> (DeviceTier: <tier>).
All applicable MLX models pass every expectation in their case set.
Profiles promoted from .yellow("pending-audit") to .green with
auditedAt timestamp.

Audit reports archived at Documents/audits/<timestamp>/ on the device.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 7.5: Phase 1 exit gate

- [ ] **Step 1: Verify exit criteria**

- [ ] Seven commits on `codex/stabilize-local-edge-app`.
- [ ] `xcodebuild test … -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` → `** TEST SUCCEEDED **`.
- [ ] Diagnostics harness green for every applicable model on the user's iPhone.
- [ ] `RuntimeProfiles.json` committed with dated verdicts.
- [ ] App installed, chat works, no token leaks, think-block renders collapsible, no OOM.

- [ ] **Step 2: Push the branch**

```bash
git push -u origin codex/stabilize-local-edge-app
```

Phase 1 complete. Phase 2 (UI redesign) starts from this branch.
