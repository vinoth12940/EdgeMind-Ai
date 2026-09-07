# Dispatch Assignment — Explorer 1 (Hardware & Memory)

## 2026-09-07T04:46:00Z

- **Role**: teamwork_preview_explorer
- **Working Directory**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_1
- **Authoritative Request**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/ORIGINAL_REQUEST.md
- **Scope Focus**: R1 - Device Tier Classification & Memory Crash Prevention

### Objectives
1. Read `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/ORIGINAL_REQUEST.md` thoroughly.
2. Investigate `Services/Inference/DeviceTier.swift` and `Services/Inference/DeviceCapabilityService.swift`:
   - How hardware models and memory are currently detected and mapped to tiers.
   - Exact classification of 3GB and 4GB devices (iPhone 10 [X, XR, XS], 11, 12 series, SE 2/3, standard iPads) into `.compact` tier.
   - Context window allocation (safe 2,048 tokens for `.compact`).
   - Disabling flash attention for A11–A13 devices.
   - Check coverage of iPhone 10, 11, 12, 13, 14, 15, 16, 17 series in `DeviceTierTests.swift` and `DeviceCapabilityTests.swift`.
3. Investigate `Services/Inference/RuntimeMemoryCoordinator.swift`:
   - How runtimes are loaded/unloaded and mutual exclusion is enforced.
   - How `LiteRTRuntime` and `MLX` runtimes are tracked and fully unloaded when switching between them.
4. Investigate memory guards and backgrounding:
   - Real-time headroom check via `AvailableMemoryGuard.swift` (`os_proc_available_memory()`) guarding inference & vision prefill.
   - App backgrounding eviction (`scenePhase == .background` in `EdgeMindAiApp.swift` or state store).
5. Produce a comprehensive report in `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_1/analysis.md` and a self-contained `handoff.md`.
