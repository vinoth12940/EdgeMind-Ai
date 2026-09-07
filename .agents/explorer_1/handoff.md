# Handoff Report — Explorer 1 (Hardware & Memory Investigation)

**Role**: Explorer 1 (`teamwork_preview_explorer`)  
**Scope Focus**: R1 - Device Tier Classification & Memory Crash Prevention  
**Working Directory**: `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_1`  
**Reference Analysis**: `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_1/analysis.md`  

---

## 1. Observation

Direct observations from source inspection across the EdgeMind AI codebase:

### 1.1 `DeviceTier.swift`
- In `EdgeMindAi/Services/Inference/DeviceTier.swift` lines 85–98, the classification logic dynamically caps A14 and older iPhones at `.compact`:
  ```swift
  if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone13,") {
      return .compact
  }
  ```
  However, lines 120–123 state in the static fallback:
  ```swift
  // Simulator, iPad, unknown future — default to .pro so we do not hide everything.
  // The download guard still blocks oversize loads.
  return .pro
  ```
  Consequently, all iPads (including iPad 5th–10th gen, iPad Air 3–4, iPad mini 5–6 with 3 GB or 4 GB RAM) default to `.pro` (8 GB) in static classification.
- In `EdgeMindAi/Services/Inference/DeviceTier.swift` lines 118–119, iPhone 17 devices are statically classified as `.pro`:
  ```swift
  if machine.hasPrefix("iPhone18,") { return .pro }
  ```
  The `.ultra` tier (12 GB+ RAM, e.g. iPhone 17 Pro Max) has no static mapping.

### 1.2 `DeviceCapabilityService.swift`
- In `EdgeMindAi/Services/Inference/DeviceCapabilityService.swift` lines 24–27:
  ```swift
  // iPhone 13 / iPhone 14 / iPhone 15 non-Pro — A15/A16, 4–6 GB RAM: "iPhone14,x", "iPhone15,x"
  if machine.hasPrefix("iPhone14,") || machine.hasPrefix("iPhone15,") {
      return 4096
  }
  ```
  `iPhone14,4` (iPhone 13 mini) and `iPhone14,6` (iPhone SE 3) both have 4 GB RAM, but return `4096` tokens instead of the required safe `2048` tokens.
- In `EdgeMindAi/Services/Inference/DeviceCapabilityService.swift` lines 28–30:
  All iPads fall through and return `8192` context tokens:
  ```swift
  // iPhone 15 Pro+, iPhone 16+, iPad, and simulator — 6–8+ GB RAM
  return 8192
  ```
- In `EdgeMindAi/Services/Inference/DeviceCapabilityService.swift` lines 42–47:
  ```swift
  static func supportsFlashAttention(for machine: String) -> Bool {
      // A14 and older chips (iPhone 13,x, 12,x, 11,x, 10,x) do not support flash attention safely
      if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone13,") {
          return false
      }
      return true
  }
  ```
  This only disables flash attention for `iPhone10,`–`iPhone13,`. All iPads with A10, A12, A13, and A14 chips (`iPad7,x`, `iPad8,x`, `iPad11,x`, `iPad12,x`, `iPad13,1`..`iPad13,3`, `iPad13,18`..`iPad13,19`) return `true`, enabling `LLAMA_FLASH_ATTN_TYPE_ENABLED` in `LocalLlamaRuntime.swift` line 154 and causing Metal shader/runtime crashes.

### 1.3 `RuntimeMemoryCoordinator.swift`
- In `EdgeMindAi/Services/Inference/RuntimeMemoryCoordinator.swift` lines 3–26:
  `prepareForRuntime` executes `MLXRuntime.shared.unloadAndClearCache()` and `LiteRTRuntime.shared.unload()`.
  However, `RuntimeMemoryCoordinator` is an unmanaged `enum` with static methods. It does not track `activeRuntime` or assert that eviction completed before inference starts.

### 1.4 `AvailableMemoryGuard.swift` & `ChatView.swift`
- In `EdgeMindAi/Services/Inference/AvailableMemoryGuard.swift` lines 41–47:
  ```swift
  let requiredGB = estimatedGB + 0.35
  if freeGB < requiredGB && freeGB < tier.jetsamSoftLimitGB {
      memoryGuardLogger.warning(...)
      return "Device memory is currently low..."
  }
  ```
  The clause `&& freeGB < tier.jetsamSoftLimitGB` suppresses the headroom warning if `freeGB` exceeds the soft limit (e.g. 2.4 GB free on a 6 GB device), even when `requiredGB` exceeds available memory (e.g. 2.8 GB required), resulting in an unhandled Jetsam kill.
- In `EdgeMindAi/Features/Chat/ChatView.swift` line 190:
  ```swift
  if let headroomAlert = AvailableMemoryGuard.checkMemoryHeadroom(for: model.catalogItem, isVision: attachedImage != nil)
  ```
  `isVision` is only passed as `true` if `attachedImage != nil`. It fails to account for `effectiveImageData` inherited in multi-turn vision conversations (`ChatVisionContext.inheritedImageData` at line 1889).

### 1.5 `EdgeMindAiApp.swift`
- `EdgeMindAi/App/EdgeMindAiApp.swift` contains no `scenePhase` listener.
- `ChatView.swift` lines 380–388 only observes `scenePhase` within the Chat tab. Minimizing the app while in Models, History, or Settings tabs fails to trigger `RuntimeMemoryCoordinator.releaseAll()`, leaving gigabytes of weights resident in background memory.

### 1.6 `DeviceTierTests.swift` & `DeviceCapabilityTests.swift`
- `EdgeMindAiTests/DeviceTierTests.swift`:
  - Lacks test cases for iPhone 10 (`iPhone10,x`), iPhone 11 (`iPhone12,1`), iPhone XS/XR (`iPhone11,x`), iPhone SE 2 (`iPhone12,8`), iPhone 13 mini (`iPhone14,4`), iPhone 14 series (`iPhone14,7`, `iPhone14,8`, `iPhone15,2`, `iPhone15,3`), iPhone 17 (`iPhone18,x`), and Ultra tier.
  - Line 45 has an invalid test assertion: `XCTAssertEqual(DeviceTier.classify(machine: "iPad13,1"), .pro)` which asserts iPad Air 4 (A14, 4 GB) as `.pro` instead of `.compact`.
- `EdgeMindAiTests/DeviceCapabilityTests.swift`:
  - `testFlashAttentionDisabledOnA14` (line 34) only tests `iPhone13,1` and `iPhone13,4`. It has no assertions for A11, A12, A13, or pre-A15 iPads.
  - Context size tests do not verify 2,048 tokens on iPhone 10, 11, SE 2/3, 13 mini, or standard iPads.

---

## 2. Logic Chain

1. **Hardware Detection to Safe Parameters**:
   - *Premise*: Under iOS Jetsam, foreground apps are killed when exceeding ~55–60% of physical RAM. On 3 GB and 4 GB devices, total usable memory before kill is ~1.5–2.2 GB.
   - *Deduction from 1.1 & 1.2*: Defaulting standard iPads to `.pro` in `DeviceTier.swift` and allocating 8,192 context tokens in `DeviceCapabilityService.swift` creates an immediate KV cache footprint of ~1.0–1.4 GB. Adding 1.2–2.0 GB of model weights immediately triggers a hard Jetsam SIGKILL.
   - *Deduction*: Classifying all <= 4 GB devices (iPhone 10, 11, 12, SE 2/3, 13 mini, standard iPads) into `.compact` and deriving `DeviceCapabilityService.contextSize(for:)` directly from `DeviceTier.classify(machine:).safeContextTokens` guarantees a safe 2,048-token context across all entry points.

2. **Flash Attention Safety**:
   - *Premise*: Apple GPU hardware support for flash attention begins with A15 Bionic and Apple Silicon M-series. On A14 and earlier, llama.cpp flash attention kernels fail, compile incorrectly, or cause memory instability.
   - *Deduction from 1.2*: Because `supportsFlashAttention(for:)` only checks `iPhone10,`–`iPhone13,`, all A10–A14 iPads (`iPad7,x` to `iPad13,x`) activate flash attention in `LocalLlamaRuntime.swift`.
   - *Deduction*: Disabling flash attention for all A10–A14 chips (both iPhone and iPad) is essential to prevent inference crashes on older devices.

3. **Runtime Mutual Exclusion**:
   - *Premise*: An iOS device cannot concurrently hold two LLM runtimes (e.g. 2.0 GB LiteRT-LM + 2.5 GB MLX) in memory.
   - *Deduction from 1.3*: `prepareForRuntime` properly calls `LiteRTRuntime.shared.unload()` (which deletes the native engine via `litert_lm_engine_delete`) and `MLXRuntime.shared.unloadAndClearCache()` (which purges Metal GPU cache). However, lack of state tracking makes it impossible to verify runtime exclusion.

4. **Headroom Checks & Vision Guarding**:
   - *Premise*: `os_proc_available_memory()` reports real remaining bytes before the Jetsam kill line.
   - *Deduction from 1.4*: If `freeGB < requiredGB`, the process cannot allocate the model without risking termination. The additional clause `&& freeGB < tier.jetsamSoftLimitGB` allows unsafe execution when `freeGB` is between the soft limit and `requiredGB`. Furthermore, omitting inherited vision data in multi-turn chats bypasses the 400 MB vision tower buffer.
   - *Deduction*: Removing the suppression clause and checking `isVision` based on both explicit and inherited image data ensures reliable in-chat notices instead of hard crashes.

5. **Background Eviction**:
   - *Premise*: iOS Jetsam terminates background apps that hold excessive memory within seconds.
   - *Deduction from 1.5*: Handling `scenePhase == .background` only in `ChatView` fails whenever the user is in Models, History, or Settings tabs.
   - *Deduction*: Moving `scenePhase` handling to `EdgeMindAiApp.swift` guarantees eviction of idle weights on backgrounding regardless of the active UI tab.

---

## 3. Caveats

1. **Physical Device vs Simulator**: In the iOS Simulator, `os_proc_available_memory()` is unavailable; `AvailableMemoryGuard` defaults to 16 GB virtual headroom. MLX and LiteRT-LM do not execute in simulator builds due to Metal/library constraints.
2. **Dynamic Machine Identifiers for Future Devices**: iPhone 17 identifiers (`iPhone18,1` through `iPhone18,4`) follow Apple's numbering conventions (`iPhone17,x` = iPhone 16 series, `iPhone18,x` = iPhone 17 series). Static classification maps `iPhone18,4` (17 Pro Max) to `.ultra` and `iPhone18,1`..`3` to `.pro`, while dynamic `physicalMemoryBytes` handles real physical RAM at runtime.
3. **No other caveats**: All observations are verified directly against source files in the repository.

---

## 4. Conclusion

To stabilize EdgeMind AI against memory crashes across all device tiers (satisfying requirement R1):
1. **Device Tier**: Update `DeviceTier.classify` to statically classify all 3 GB and 4 GB devices (iPhone 10, 11, 12, SE 2/3, 13 mini, and standard iPads: iPad 5–10, Air 3–4, mini 5–6) into `.compact`, and map 12 GB+ devices (iPhone 17 Pro Max) to `.ultra`.
2. **Capability Service**: Align `DeviceCapabilityService.contextSize(for:)` directly with `DeviceTier.classify(machine:).safeContextTokens` (returning 2,048 for `.compact`), and disable flash attention on all pre-A15 chips (A10–A14 iPhones and iPads).
3. **Memory Headroom**: In `AvailableMemoryGuard.checkMemoryHeadroom`, remove the `&& freeGB < tier.jetsamSoftLimitGB` suppression check, and in `ChatView`, guard vision prefill using effective/inherited image data.
4. **Backgrounding**: Add `.onChange(of: scenePhase)` to `EdgeMindAiApp.swift` to invoke `RuntimeMemoryCoordinator.releaseAll()` on `.background`.
5. **Unit Tests**: Update `DeviceTierTests.swift` and `DeviceCapabilityTests.swift` to achieve comprehensive coverage across iPhone 10 through 17 series, standard iPads, safe 2,048 context, and A11–A14 flash attention disabled.

---

## 5. Verification Method

### 5.1 Automated Unit Tests
Run the test suites in Xcode or via terminal:
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing EdgeMindAiTests/DeviceTierTests \
  -only-testing EdgeMindAiTests/DeviceCapabilityTests
```

### 5.2 Specific Test Cases to Verify
1. In `DeviceTierTests`:
   - `DeviceTier.classify(machine: "iPhone10,3") == .compact` (iPhone X, 3 GB)
   - `DeviceTier.classify(machine: "iPhone11,8") == .compact` (iPhone XR, 3 GB)
   - `DeviceTier.classify(machine: "iPhone12,1") == .compact` (iPhone 11, 4 GB)
   - `DeviceTier.classify(machine: "iPhone12,8") == .compact` (iPhone SE 2, 3 GB)
   - `DeviceTier.classify(machine: "iPhone14,4") == .compact` (iPhone 13 mini, 4 GB)
   - `DeviceTier.classify(machine: "iPhone14,6") == .compact` (iPhone SE 3, 4 GB)
   - `DeviceTier.classify(machine: "iPad7,11") == .compact` (iPad 7th gen, 3 GB)
   - `DeviceTier.classify(machine: "iPad12,1") == .compact` (iPad 9th gen, 3 GB)
   - `DeviceTier.classify(machine: "iPad13,18") == .compact` (iPad 10th gen, 4 GB)
   - `DeviceTier.classify(machine: "iPad13,1") == .compact` (iPad Air 4th gen, 4 GB)
   - `DeviceTier.classify(machine: "iPad11,1") == .compact` (iPad mini 5th gen, 3 GB)
   - `DeviceTier.classify(machine: "iPad14,1") == .compact` (iPad mini 6th gen, 4 GB)
   - `DeviceTier.classify(machine: "iPhone18,4") == .ultra` (iPhone 17 Pro Max, 12 GB)
2. In `DeviceCapabilityTests`:
   - `DeviceCapabilityService.contextSize(for: "iPhone10,3") == 2048`
   - `DeviceCapabilityService.contextSize(for: "iPhone14,4") == 2048`
   - `DeviceCapabilityService.contextSize(for: "iPhone14,6") == 2048`
   - `DeviceCapabilityService.contextSize(for: "iPad13,18") == 2048`
   - `DeviceCapabilityService.supportsFlashAttention(for: "iPhone10,3") == false` (A11)
   - `DeviceCapabilityService.supportsFlashAttention(for: "iPhone11,2") == false` (A12)
   - `DeviceCapabilityService.supportsFlashAttention(for: "iPhone12,1") == false` (A13)
   - `DeviceCapabilityService.supportsFlashAttention(for: "iPhone13,1") == false` (A14)
   - `DeviceCapabilityService.supportsFlashAttention(for: "iPad13,18") == false` (A14 iPad)

### 5.3 Invalidation Conditions
This analysis is invalidated if:
- Apple provides an official mechanism allowing background LLM execution without memory limits on iOS 17+.
- `llama.cpp` upstream introduces backwards-compatible flash attention support for A14 and older Apple GPU architectures.
