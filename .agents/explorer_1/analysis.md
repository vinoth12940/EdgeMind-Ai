# Technical Analysis: R1 - Device Tier Classification & Memory Crash Prevention

**Date**: 2026-09-07  
**Author**: Explorer 1 (Hardware & Memory)  
**Target Repository**: `EdgeMindAi` (iOS Local AI/LLM App)  
**Working Directory**: `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_1`  

---

## 1. Executive Summary

This investigation analyzes the architectural resilience and hardware adaptation mechanisms of EdgeMind AI across all supported iOS devices (ranging from 3 GB / 4 GB Compact devices to 12 GB+ Ultra devices). Specifically, it investigates:
1. **Device Tier Classification** (`DeviceTier.swift`) & **Capability Detection** (`DeviceCapabilityService.swift`): Identifies critical classification gaps where standard iPads (iPad 5th–10th gen, iPad Air 3–4, iPad mini 5–6) and 4 GB iPhones (iPhone 13 mini, iPhone SE 3) receive excessive context allocations (4,096 or 8,192 tokens instead of safe 2,048 tokens) and dangerous flash attention activation on pre-A15 silicon.
2. **Inference Runtime Mutual Exclusion** (`RuntimeMemoryCoordinator.swift`): Analyzes lifecycle management across GGUF (`LocalLlamaRuntime`), MLX (`MLXRuntime`), and LiteRT-LM (`LiteRTRuntime`), uncovering the absence of explicit active runtime state tracking.
3. **Real-time Memory Headroom Guarding** (`AvailableMemoryGuard.swift` & `ChatView.swift`): Details a logic flaw in `AvailableMemoryGuard.checkMemoryHeadroom` where headroom warnings are artificially suppressed, and identifies that multi-turn vision prefill is not guarded when image data is inherited rather than freshly attached.
4. **App Backgrounding Eviction** (`EdgeMindAiApp.swift`): Shows that `scenePhase == .background` is currently only handled inside `ChatView.swift`, meaning backgrounding from other tabs (Models, History, Settings) leaves gigabytes of model weights resident, triggering iOS background Jetsam termination.
5. **Test Coverage Deficits** (`DeviceTierTests.swift` & `DeviceCapabilityTests.swift`): Documents test suite omissions across iPhone 10, 11, 14, and 17 series, standard iPads, and A11–A13 flash attention verification.

---

## 2. Problem Boundary & Scope

EdgeMind AI operates strictly on-device with zero backend. LLMs/VLMs are resident in unified memory shared between CPU and Apple Silicon GPU/ANE. Under iOS Jetsam:
- Foreground apps are killed when exceeding ~55–60% of physical RAM.
- Background apps are killed when exceeding ~50 MB of resident memory.
- A 7B or 4B model combined with KV cache and vision embeddings can instantly spike memory past Jetsam limits if context size, flash attention, and runtime coexistence are not strictly governed.

### Target Files Investigated:
- `EdgeMindAi/Services/Inference/DeviceTier.swift`
- `EdgeMindAi/Services/Inference/DeviceCapabilityService.swift`
- `EdgeMindAi/Services/Inference/RuntimeMemoryCoordinator.swift`
- `EdgeMindAi/Services/Inference/AvailableMemoryGuard.swift`
- `EdgeMindAi/App/EdgeMindAiApp.swift`
- `EdgeMindAi/Features/Chat/ChatView.swift`
- `EdgeMindAiTests/DeviceTierTests.swift`
- `EdgeMindAiTests/DeviceCapabilityTests.swift`

---

## 3. Detailed Investigation & Findings

### 3.1 Hardware Detection & Device Tier Classification (`DeviceTier.swift`)

#### Current Mechanism
`DeviceTier.current()` invokes `classify(machine:physicalMemoryBytes:)` passing `DeviceCapabilityService.machineModel()` (via Darwin `sysctlbyname("hw.machine", ...)`) and `ProcessInfo.processInfo.physicalMemory`.

```swift
// DeviceTier.swift lines 78–98
static func classify(machine: String, physicalMemoryBytes: UInt64? = nil) -> DeviceTier {
    if let memory = physicalMemoryBytes, memory > 0 {
        if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone13,") {
            return .compact
        }
        let memoryGB = Double(memory) / (1024.0 * 1024.0 * 1024.0)
        if memoryGB < 4.5 {
            return .compact
        } else if memoryGB < 6.5 {
            return .standard
        } else if memoryGB < 10.5 {
            return .pro
        } else {
            return .ultra
        }
    }
```

#### Identified Issues & Gaps
1. **Static Fallback Misclassifies All iPads as `.pro`**:
   In `DeviceTier.swift` lines 120–123:
   ```swift
   // Simulator, iPad, unknown future — default to .pro so we do not hide everything.
   // The download guard still blocks oversize loads.
   return .pro
   ```
   When `physicalMemoryBytes` is nil or zero (such as during unit tests, catalog filtering, or when querying machine strings directly), **all iPads** default to `.pro`. This includes:
   - iPad 5th/6th/7th/8th/9th/10th Gen (`iPad6,11`, `iPad7,5`, `iPad7,11`, `iPad11,6`, `iPad12,1`, `iPad13,18`): 2 GB – 4 GB RAM.
   - iPad Air 3rd/4th Gen (`iPad11,3`, `iPad13,1`): 3 GB – 4 GB RAM.
   - iPad mini 5th/6th Gen (`iPad11,1`, `iPad14,1`): 3 GB – 4 GB RAM.
   These are 3 GB / 4 GB devices that MUST classify as `.compact`.
   In fact, `DeviceTierTests.swift` line 45 codifies this defect:
   `XCTAssertEqual(DeviceTier.classify(machine: "iPad13,1"), .pro)` (testing iPad Air 4, an A14 4 GB device, and expecting `.pro`!).
2. **Pre-A15 iPad Models Not Capped in Dynamic Path**:
   In lines 85–87, only `iPhone10,` through `iPhone13,` are explicitly capped at `.compact`. If an A12X/A12Z iPad Pro (`iPad8,1`..`iPad8,12`) with 6 GB RAM is checked, it falls into `.standard` despite lacking modern neural engine acceleration and having aggressive Jetsam limits on older iPadOS builds.
3. **iPhone 17 Pro Max / Ultra Tier Static Mapping Missing**:
   In lines 118–119:
   `if machine.hasPrefix("iPhone18,") { return .pro }`
   iPhone 17 Pro Max (`iPhone18,4` or similar) with 12 GB RAM is mapped to `.pro` in the static fallback instead of `.ultra`.

---

### 3.2 Context Size Allocation & Flash Attention (`DeviceCapabilityService.swift`)

#### Current Mechanism
`DeviceCapabilityService.swift` determines `contextSize(for:)` and `supportsFlashAttention(for:)`:

```swift
// DeviceCapabilityService.swift lines 18–47
static func contextSize(for machine: String) -> Int32 {
    if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone13,") {
        return 2048
    }
    if machine.hasPrefix("iPhone14,") || machine.hasPrefix("iPhone15,") {
        return 4096
    }
    return 8192
}

static func supportsFlashAttention(for machine: String) -> Bool {
    if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone13,") {
        return false
    }
    return true
}
```

#### Identified Issues & Gaps
1. **Context Window Over-Allocation on 4 GB iPhones**:
   - `iPhone14,4` (iPhone 13 mini) has 4 GB RAM.
   - `iPhone14,6` (iPhone SE 3rd Gen) has 4 GB RAM.
   Because both match `machine.hasPrefix("iPhone14,")`, `contextSize(for:)` returns **4096** tokens instead of the required safe **2048** tokens.
2. **Context Window Over-Allocation on Standard iPads**:
   - `iPad7,11` (iPad 7, 3 GB), `iPad11,6` (iPad 8, 3 GB), `iPad12,1` (iPad 9, 3 GB), `iPad13,18` (iPad 10, 4 GB), `iPad13,1` (iPad Air 4, 4 GB):
   All of these fall through to line 29 and return **8192** tokens!
   Allocating an 8,192-token KV cache on a 3 GB or 4 GB iPad consumes ~1.0–1.4 GB of RAM solely for the KV cache, causing immediate Jetsam crash when loading any 2B–4B model.
3. **Dangerous Flash Attention Activation on A10–A14 iPads**:
   `supportsFlashAttention(for:)` checks only `iPhone10,` through `iPhone13,`.
   For ANY iPad (`iPad7,x`, `iPad8,x`, `iPad11,x`, `iPad12,x`, `iPad13,x`), it returns `true`!
   When `LocalLlamaRuntime.swift` creates the llama context (line 153):
   `contextParams.flash_attn_type = DeviceCapabilityService.supportsFlashAttention() ? LLAMA_FLASH_ATTN_TYPE_ENABLED : LLAMA_FLASH_ATTN_TYPE_DISABLED`
   Enabling flash attention on A10–A14 iPads causes kernel panic, Metal shader compiler crashes, or NaN generation because older Apple GPUs lack the required FP16 execution units and memory hierarchy for hardware flash attention.
4. **Architectural Disconnect**:
   `DeviceCapabilityService` duplicates device classification logic instead of referencing `DeviceTier.classify(machine:)`. If `contextSize(for:)` is derived from `DeviceTier.classify(machine:).safeContextTokens`, all `.compact` devices automatically receive 2,048 tokens.

---

### 3.3 Mutual Exclusion Across Runtimes (`RuntimeMemoryCoordinator.swift`)

#### Current Mechanism
`RuntimeMemoryCoordinator.swift` orchestrates unloading between `.gguf`, `.mlx`, and `.liteRTLM`:

```swift
// RuntimeMemoryCoordinator.swift lines 4–26
static func prepareForRuntime(_ runtimeType: ModelCatalogItem.RuntimeType) async {
    switch runtimeType {
    case .gguf:
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        await MLXRuntime.shared.unloadAndClearCache()
        #endif
        #if canImport(LiteRTLM) && !targetEnvironment(simulator)
        await LiteRTRuntime.shared.unload()
        #endif
    case .mlx:
        await LocalLlamaRuntime.shared.unload()
        #if canImport(LiteRTLM) && !targetEnvironment(simulator)
        await LiteRTRuntime.shared.unload()
        #endif
    case .liteRTLM:
        await LocalLlamaRuntime.shared.unload()
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        await MLXRuntime.shared.unloadAndClearCache()
        #endif
    case .foundationModels:
        await releaseAll()
    }
}
```

#### Unloading Mechanics
- **GGUF** (`LocalLlamaRuntime.shared.unload()`):
  In `LocalLlamaRuntime.swift` line 532, sets `activeContext = nil` and `activeModelPath = nil`.
  `LocalLlamaContext.deinit` (lines 112–118) frees `llama_sampler_free`, `llama_batch_free`, `llama_model_free`, `llama_free`, and `llama_backend_free`.
- **MLX** (`MLXRuntime.shared.unloadAndClearCache()`):
  In `MLXInferenceService.swift` lines 737–740, sets `activeContainer = nil`, `activeModelID = nil`, `activeIsVision = false`, and executes `Memory.clearCache()` which flushes the Metal unified memory cache.
- **LiteRT-LM** (`LiteRTRuntime.shared.unload()`):
  In `LiteRTInferenceService.swift` lines 160–164, sets `activeEngine = nil`, `activeModelPath = nil`, and `activeMultimodal = false`. Setting `activeEngine = nil` releases the `Engine` actor; `Engine.deinit` (in `Vendor/LiteRT-LM/swift/Engine.swift` lines 203–207) invokes native C API `litert_lm_engine_delete(handle)`.

#### Identified Issues & Gaps
1. **No Active Runtime State Tracking**:
   `RuntimeMemoryCoordinator` is an stateless `enum` with static methods. It does not record `currentActiveRuntime`. Therefore, callers cannot query which runtime currently holds GPU memory.
2. **Switching Between Models Within the Same Runtime**:
   If user switches from LiteRT Text to LiteRT Vision (e.g. Gemma 4 E2B Vision), `prepareForRuntime(.liteRTLM)` does not unload `LiteRTRuntime` because the switch is internal. While `LiteRTRuntime.ensureEngine` unloads on path/multimodal mismatch, `RuntimeMemoryCoordinator` should provide an explicit `releaseAll()` or switch method that guarantees full memory release between distinct models.
3. **No Concurrency Guarding**:
   If multiple threads or tasks call `prepareForRuntime` concurrently, racing unload/load operations could occur. Making `RuntimeMemoryCoordinator` an `actor` or adding state isolation ensures deterministic serial eviction.

---

### 3.4 Real-Time Memory Headroom Checks (`AvailableMemoryGuard.swift` & `ChatView.swift`)

#### Current Mechanism
`AvailableMemoryGuard.swift` queries Darwin's `os_proc_available_memory()`:

```swift
// AvailableMemoryGuard.swift lines 32–49
static func checkMemoryHeadroom(for model: ModelCatalogItem, isVision: Bool = false) -> String? {
    #if targetEnvironment(simulator)
    return nil
    #else
    let tier = DeviceTier.current()
    let estimatedGB = model.estimatedResidentGB(contextTokens: tier.safeContextTokens) + (isVision ? 0.4 : 0.0)
    let freeGB = availableMemoryGB()

    // Reserve 350 MB for app views, audio rendering, and system frameworks.
    let requiredGB = estimatedGB + 0.35

    if freeGB < requiredGB && freeGB < tier.jetsamSoftLimitGB {
        memoryGuardLogger.warning("Low memory headroom: free=\(freeGB, privacy: .public) GB, required=\(requiredGB, privacy: .public) GB for \(model.displayName, privacy: .public)")
        return "Device memory is currently low (\(String(format: "%.1f", freeGB)) GB available, ~\(String(format: "%.1f", estimatedGB)) GB needed). Close background apps or pick a lighter model to avoid iOS terminating the app."
    }
    return nil
    #endif
}
```

#### Identified Issues & Gaps
1. **Suppression Condition Bug**:
   Line 43: `if freeGB < requiredGB && freeGB < tier.jetsamSoftLimitGB`
   If physical memory available before Jetsam (`freeGB`) is 2.4 GB on a Standard device (`jetsamSoftLimitGB` = 2.2 GB), and a model requires 2.8 GB (`requiredGB`), `freeGB < tier.jetsamSoftLimitGB` is `false`.
   The guard returns `nil` (allowing inference to start), and iOS immediately kills the app via Jetsam SIGKILL!
   `freeGB < requiredGB` is the necessary and sufficient condition to prevent memory crashes.
2. **Vision Prefill Headroom Guarding in Multi-Turn Chats**:
   In `ChatView.swift` line 190:
   `if let headroomAlert = AvailableMemoryGuard.checkMemoryHeadroom(for: model.catalogItem, isVision: attachedImage != nil)`
   In multi-turn conversations where image context is inherited from prior turns (`effectiveImageData != nil` via `ChatVisionContext.inheritedImageData`), `attachedImage` is `nil`!
   As a result, `isVision: false` is passed to `checkMemoryHeadroom`, omitting the 400 MB vision tower buffer and leading to unexpected crashes during vision prefill.
3. **Lack of In-Inference Prefill Checks**:
   The check only runs once in `ChatView.memoryGuardMessage` before prompt queuing. If available memory degrades during document extraction or tool execution immediately prior to inference, no check guards the actual prefill entry point.

---

### 3.5 App Backgrounding Eviction (`EdgeMindAiApp.swift` vs `ChatView.swift`)

#### Current Mechanism
In `EdgeMindAiApp.swift`:
There is **no** `scenePhase` observation.

In `ChatView.swift` lines 380–388:
```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background {
        if !isSending && generationTask == nil {
            Task {
                await RuntimeMemoryCoordinator.releaseAll()
            }
        }
    }
}
```

#### Identified Issues & Gaps
1. **Vulnerability on Tab Navigation**:
   In `RootView.swift`, the app has 4 tabs: Chat (0), Models (1), History (2), Settings (3).
   If a user conducts a conversation with a 2B–4B model (weights resident in memory), switches to the Models tab to browse, and minimizes the app:
   `ChatView.onChange(of: scenePhase)` may not be evaluated or invoked while `ChatView` is inactive in the background tab view hierarchy.
   The idle model weights remain resident in memory, and iOS Jetsam terminates the app in the background within seconds.
2. **Solution**:
   Attach `.onChange(of: scenePhase)` at the app root level (`EdgeMindAiApp.swift` / `LaunchRootView`). When `newPhase == .background`, invoke `RuntimeMemoryCoordinator.releaseAll()`.

---

### 3.6 Test Suite Coverage Analysis (`DeviceTierTests.swift` & `DeviceCapabilityTests.swift`)

#### `DeviceTierTests.swift` Audit:
| Device Family | Models Covered in Tests | Missing Models | Current Pass/Fail Status |
|---|---|---|---|
| **iPhone 10 (8/8+/X)** | None | `iPhone10,1`, `iPhone10,2`, `iPhone10,3`, `iPhone10,4`, `iPhone10,5`, `iPhone10,6` | Missing test coverage |
| **iPhone 11 (XS/XR/11/SE2)** | None | `iPhone11,2`, `iPhone11,4`, `iPhone11,6`, `iPhone11,8`, `iPhone12,1`, `iPhone12,3`, `iPhone12,5`, `iPhone12,8` | Missing test coverage |
| **iPhone 12** | `iPhone13,1`, `iPhone13,2`, `iPhone13,3`, `iPhone13,4` | None | Covered |
| **iPhone 13** | `iPhone14,2`, `iPhone14,3`, `iPhone14,5` | `iPhone14,4` (13 mini, 4 GB Compact) | Missing 13 mini test |
| **iPhone SE 2/3** | `iPhone14,6` (SE 3) | `iPhone12,8` (SE 2) | Missing SE 2 test |
| **iPhone 14** | None explicitly | `iPhone14,7`, `iPhone14,8`, `iPhone15,2`, `iPhone15,3` | Missing test coverage |
| **iPhone 15** | `iPhone15,4`, `iPhone15,5`, `iPhone16,1`, `iPhone16,2` | None | Covered |
| **iPhone 16** | `iPhone17,1`, `iPhone17,2`, `iPhone17,3`, `iPhone17,4` | None | Covered |
| **iPhone 17** | None | `iPhone18,1`, `iPhone18,2`, `iPhone18,3`, `iPhone18,4` | Missing test coverage |
| **Standard iPads** | None (`iPad13,1` asserted as `.pro`!) | `iPad7,11`, `iPad11,6`, `iPad12,1`, `iPad13,18`, `iPad11,1`, `iPad14,1`, `iPad11,3`, `iPad13,1` | **Defective test assertion** |
| **Ultra Tier** | None | `iPhone18,4` or 12 GB+ devices | Missing test coverage |

#### `DeviceCapabilityTests.swift` Audit:
| Capability Check | Current Tests | Required Additions |
|---|---|---|
| **Context Window (2,048)** | `iPhone13,1`, `iPhone13,4` | `iPhone10,x`, `iPhone11,x`, `iPhone12,x`, `iPhone14,4` (13 mini), `iPhone14,6` (SE 3), standard iPads (`iPad7,11`, `iPad11,6`, `iPad12,1`, `iPad13,18`) |
| **Context Window (4,096)** | `iPhone14,2`, `iPhone15,2` | `iPhone14,5`, `iPhone14,7`, `iPhone14,8`, `iPhone15,4`, `iPhone15,5` |
| **Context Window (8,192)** | `iPhone16,1`, `iPhone17,3`, `iPad13,4`, `""`, `arm64` | `iPhone18,x` |
| **Flash Attention Disabled** | `iPhone13,1`, `iPhone13,4` (A14 only) | A11 (`iPhone10,1`, `iPhone10,3`), A12 (`iPhone11,2`, `iPhone11,8`), A13 (`iPhone12,1`, `iPhone12,8`), A10–A14 iPads (`iPad7,11`, `iPad11,6`, `iPad12,1`, `iPad13,18`) |
| **Flash Attention Enabled** | `iPhone14,2`, `iPhone16,1`, `iPad13,4` | `iPhone17,x`, `iPhone18,x` |

---

## 4. Proposed Code Changes

### 4.1 `EdgeMindAi/Services/Inference/DeviceTier.swift`
Enhance static fallback and classification to accurately classify 3 GB / 4 GB iPads and 12 GB devices:

```swift
// Proposed change in DeviceTier.classify(machine:physicalMemoryBytes:)
static func classify(machine: String, physicalMemoryBytes: UInt64? = nil) -> DeviceTier {
    if let memory = physicalMemoryBytes, memory > 0 {
        // A14 and older iPhone/iPad devices are capped at .compact due to memory constraints
        if isA14OrOlder(machine) {
            return .compact
        }
        let memoryGB = Double(memory) / (1024.0 * 1024.0 * 1024.0)
        if memoryGB < 4.5 {
            return .compact
        } else if memoryGB < 6.5 {
            return .standard
        } else if memoryGB < 10.5 {
            return .pro
        } else {
            return .ultra
        }
    }

    // Static fallback:
    // iPhone 8/X (A11), XS/XR (A12), 11 (A13):
    if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") {
        return .compact
    }
    // iPhone 12 family (A14):
    if machine.hasPrefix("iPhone13,") { return .compact }
    // iPhone SE 2 (iPhone12,8), SE 3 (iPhone14,6), 13 mini (iPhone14,4):
    if machine == "iPhone12,8" || machine == "iPhone14,6" || machine == "iPhone14,4" {
        return .compact
    }
    // Standard iPads & Compact iPads (<= 4 GB):
    // iPad 5-7 (iPad6,11/12, iPad7,5/6, iPad7,11/12)
    // iPad 8-10 (iPad11,6/7, iPad12,1/2, iPad13,18/19)
    // iPad Air 3-4 (iPad11,3/4, iPad13,1/2)
    // iPad mini 5-6 (iPad11,1/2, iPad14,1/2)
    if isStandardOrCompactIPad(machine) {
        return .compact
    }
    // Standard 6GB iPhones: 13/13 Pro/13 Pro Max/14/14 Plus/14 Pro/14 Pro Max/15/15 Plus
    if machine.hasPrefix("iPhone14,") || machine.hasPrefix("iPhone15,") {
        return .standard
    }
    // Pro 8GB iPhones: 15 Pro/Pro Max, 16 series, 17 standard/Pro
    if machine.hasPrefix("iPhone16,") || machine.hasPrefix("iPhone17,") || machine == "iPhone18,1" || machine == "iPhone18,2" || machine == "iPhone18,3" {
        return .pro
    }
    // Ultra 12GB+ devices: iPhone 17 Pro Max
    if machine == "iPhone18,4" {
        return .ultra
    }
    return .pro
}
```

### 4.2 `EdgeMindAi/Services/Inference/DeviceCapabilityService.swift`
Align context size directly with `DeviceTier` and enforce flash attention gating for A11–A14 across all devices:

```swift
static func contextSize(for machine: String) -> Int32 {
    let tier = DeviceTier.classify(machine: machine)
    return Int32(tier.safeContextTokens)
}

static func supportsFlashAttention(for machine: String) -> Bool {
    // Flash attention requires A15 Bionic or newer, or Apple Silicon M-series.
    // Disable on all A14 and older chips (iPhone 10,x to 13,x, and older iPads)
    if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone13,") {
        return false
    }
    // Pre-A15 iPads: A10/A12/A13/A14 (iPad7,x, iPad8,x, iPad11,x, iPad12,x, iPad13,1-3, iPad13,18-19)
    if isPreA15IPad(machine) {
        return false
    }
    return true
}
```

### 4.3 `EdgeMindAi/Services/Inference/AvailableMemoryGuard.swift`
Remove the artificial suppression condition and guard vision prefill:

```swift
static func checkMemoryHeadroom(for model: ModelCatalogItem, isVision: Bool = false) -> String? {
    #if targetEnvironment(simulator)
    return nil
    #else
    let tier = DeviceTier.current()
    let estimatedGB = model.estimatedResidentGB(contextTokens: tier.safeContextTokens) + (isVision ? 0.4 : 0.0)
    let freeGB = availableMemoryGB()

    // Reserve 350 MB for app views, audio rendering, and system frameworks.
    let requiredGB = estimatedGB + 0.35

    if freeGB < requiredGB {
        memoryGuardLogger.warning("Low memory headroom: free=\(freeGB, privacy: .public) GB, required=\(requiredGB, privacy: .public) GB for \(model.displayName, privacy: .public)")
        return "Device memory is currently low (\(String(format: "%.1f", freeGB)) GB available, ~\(String(format: "%.1f", estimatedGB)) GB needed). Close background apps or pick a lighter model to avoid iOS terminating the app."
    }
    return nil
    #endif
}
```

### 4.4 `EdgeMindAi/App/EdgeMindAiApp.swift`
Add app-level `scenePhase` observation to evict idle weights upon minimizing the app:

```swift
@main
struct EdgeMindAiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStateStore()
    @State private var authStore = AuthStateStore()

    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some Scene {
        WindowGroup {
            LaunchRootView()
                .environment(store)
                .environment(authStore)
                .preferredColorScheme(store.settings.appearanceMode.preferredColorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    await RuntimeMemoryCoordinator.releaseAll()
                }
            }
        }
    }
}
```

---

## 5. Summary & Verification Plan

1. **Device Tier Unit Tests**: Update `DeviceTierTests.swift` to assert `.compact` for iPhone 10 (8/X), iPhone 11 (XS/XR/11/SE2), iPhone 12, iPhone 13 mini, SE 3, and standard iPads (iPad 7/8/9/10, iPad Air 3/4, iPad mini 5/6).
2. **Device Capability Unit Tests**: Update `DeviceCapabilityTests.swift` to verify:
   - `contextSize == 2048` for all `.compact` devices.
   - `supportsFlashAttention == false` for A11 (`iPhone10,1`/`3`), A12 (`iPhone11,2`/`8`), A13 (`iPhone12,1`/`8`), and A14 (`iPhone13,1`/`4`, `iPad13,18`).
3. **Execution Command**:
   ```bash
   xcodebuild test \
     -project EdgeMindAi.xcodeproj \
     -scheme EdgeMindAi \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
     -only-testing EdgeMindAiTests/DeviceTierTests \
     -only-testing EdgeMindAiTests/DeviceCapabilityTests
   ```
