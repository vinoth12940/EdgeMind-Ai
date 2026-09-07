# Dispatch Assignment — Worker M1 Gen 2 (Hardware Tier Remediation)

## 2026-09-07T13:05:00Z

- **Role**: teamwork_preview_worker
- **Working Directory**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/worker_m1_gen2
- **Authoritative Request**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/ORIGINAL_REQUEST.md
- **Project Plan**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/PROJECT.md
- **Challenger Audit Finding**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/challenger_m1_1/handoff.md

### Write Ownership
You exclusively own and may edit ONLY the following files:
- `EdgeMindAi/Services/Inference/DeviceTier.swift`
- `EdgeMindAi/Services/Inference/DeviceCapabilityService.swift`
- `EdgeMindAiTests/DeviceTierTests.swift`
- `EdgeMindAiTests/DeviceCapabilityTests.swift`

### MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

### Remediation Tasks
1. **`DeviceTier.swift`**:
   - Accurately classify standard iPhone 13 (`iPhone14,5`, 4 GB RAM) into `.compact` tier alongside `iPhone14,4` (13 mini) and `iPhone14,6` (SE 3).
     Only iPhone 13 Pro (`iPhone14,2`) and iPhone 13 Pro Max (`iPhone14,3`) (both 6 GB RAM) should classify as `.standard`.
   - Add `iPad8,` (pre-A15 iPad Pro models with A12X/A12Z, 4 GB RAM: `iPad8,1` through `iPad8,8`) into `.compact` tier in BOTH the dynamic memory check (around line 86) and static machine check (around line 121).
2. **`DeviceCapabilityService.swift`**:
   - Update `contextSize()` to use `Int32(DeviceTier.current().safeContextTokens)`.
3. **Unit Tests**:
   - In `DeviceTierTests.swift`:
     * Verify `iPhone14,5` asserts `.compact`.
     * Verify `iPhone14,2` and `iPhone14,3` assert `.standard`.
     * Verify `iPad8,1` asserts `.compact`.
   - In `DeviceCapabilityTests.swift`:
     * Verify `DeviceCapabilityService.contextSize(for: "iPhone14,5") == 2048`.
     * Verify `DeviceCapabilityService.contextSize(for: "iPhone14,2") == 4096`.
     * Verify `DeviceCapabilityService.contextSize(for: "iPad8,1") == 2048`.
4. **Verification**:
   - Run `xcodebuild test` for `DeviceTierTests` and `DeviceCapabilityTests`:
     `xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/WorkerM1_g2 -only-testing EdgeMindAiTests/DeviceTierTests -only-testing EdgeMindAiTests/DeviceCapabilityTests`
   - Verify all tests pass with 0 failures.
5. Write your handoff report to `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/worker_m1_gen2/handoff.md` and send a message upon completion.
