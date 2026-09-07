# Dispatch Assignment — Worker M1 (Hardware Tier & Memory Crash Prevention)

## 2026-09-07T05:07:00Z

- **Role**: teamwork_preview_worker
- **Working Directory**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/worker_m1
- **Authoritative Request**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/ORIGINAL_REQUEST.md
- **Project Plan**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/PROJECT.md
- **Explorer Report**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_1/handoff.md and `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_1/analysis.md`

### Write Ownership
You exclusively own and may edit ONLY the following files:
- `EdgeMindAi/Services/Inference/DeviceTier.swift`
- `EdgeMindAi/Services/Inference/DeviceCapabilityService.swift`
- `EdgeMindAi/Services/Inference/RuntimeMemoryCoordinator.swift`
- `EdgeMindAi/Services/Inference/AvailableMemoryGuard.swift`
- `EdgeMindAi/App/EdgeMindAiApp.swift`
- `EdgeMindAiTests/DeviceTierTests.swift`
- `EdgeMindAiTests/DeviceCapabilityTests.swift`

### MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

### Tasks to Implement
1. **`DeviceTier.swift`**:
   - Accurately classify all 3GB and 4GB devices (iPhone 10 [X, XR, XS], 11, 12, SE 2/3, 13 mini `iPhone14,4`, and standard iPads: iPad 5th–10th gen, iPad Air 3–4, iPad mini 5–6) into `.compact` tier.
   - Map iPhone 17 Pro Max (`iPhone18,4`) to `.ultra` tier.
2. **`DeviceCapabilityService.swift`**:
   - Derive context size directly from `DeviceTier.classify(machine:).safeContextTokens`, allocating a safe 2,048 tokens for `.compact` devices (including iPhone 10, 11, 12, SE 2/3, 13 mini, and standard iPads).
   - Disable flash attention on all pre-A15 chips (A10–A14 iPhones and iPads: `iPhone10,`–`iPhone13,`, and iPads `iPad7,`, `iPad8,`, `iPad11,`, `iPad12,`, `iPad13,`).
3. **`RuntimeMemoryCoordinator.swift`**:
   - Ensure strict mutual exclusion between inference runtimes (`prepareForRuntime` fully unloads LiteRT when switching to MLX, and vice versa).
4. **`AvailableMemoryGuard.swift`**:
   - Remove the headroom warning suppression clause (`&& freeGB < tier.jetsamSoftLimitGB`) so that when `freeGB < requiredGB`, the graceful alert is returned.
5. **`EdgeMindAiApp.swift`**:
   - Add `.onChange(of: scenePhase)` handler so that when `newPhase == .background`, idle runtime weights are evicted via `RuntimeMemoryCoordinator.releaseAll()`.
6. **`DeviceTierTests.swift` & `DeviceCapabilityTests.swift`**:
   - Add test coverage for iPhone 10, 11, 12, 13, 14, 15, 16, 17 series and standard iPads in `DeviceTierTests`.
   - Update `DeviceCapabilityTests` to verify safe 2,048 tokens on compact devices and disabled flash attention on A11–A14.
7. **Verification**:
   - Run `xcodegen generate` to ensure `AvailableMemoryGuard.swift` is properly registered in the Xcode project.
   - Run `xcodebuild test` for `DeviceTierTests` and `DeviceCapabilityTests`:
     ```bash
     xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath build/M1DerivedData -only-testing EdgeMindAiTests/DeviceTierTests -only-testing EdgeMindAiTests/DeviceCapabilityTests
     ```
   - Verify build and tests pass cleanly.

8. Document all changes and test outputs in `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/worker_m1/handoff.md`.
9. Send message to parent upon completion.
