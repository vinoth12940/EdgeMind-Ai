# Dispatch Assignment — Worker M3 (Usability & Discovery Highlights)

## 2026-09-07T13:30:00Z

- **Role**: teamwork_preview_worker
- **Working Directory**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/worker_m3
- **Authoritative Request**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/ORIGINAL_REQUEST.md
- **Project Plan**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/PROJECT.md
- **Explorer Report**: /Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_3/handoff.md and `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/explorer_3/analysis.md`

### Write Ownership
You exclusively own and may edit ONLY the following files:
- `EdgeMindAi/Models/ModelCatalogItem.swift`
- `EdgeMindAi/Features/Chat/ChatView.swift`
- `EdgeMindAi/Features/Models/ModelLibraryView.swift`
- `EdgeMindAiTests/ModelCatalogItemTests.swift`
- `EdgeMindAiTests/AppStateStoreMigrationTests.swift` (or new test file `ModelDiscoveryTests.swift`)

### MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

### Tasks to Implement
1. **`ModelCatalogItem.swift`**:
   - Add `public func isBestMatch(for tier: DeviceTier) -> Bool`:
     * Checks `minimumTier <= tier`.
     * Checks `estimatedResidentGB(contextTokens: tier.safeContextTokens) <= tier.usableWeightGB`.
     * Checks `!auditVerdict.isRed`.
     * For `.compact`: models with parameter size <= 2B, or estimated resident <= 1.2 GB.
     * For `.standard`: models with parameter size 1B–2B, or estimated resident <= 2.2 GB.
     * For `.pro`: models with parameter size 2B–4B, or VLMs, fitting within 4.5 GB.
     * For `.ultra`: premier 4B+ models or VLMs.
2. **`ChatView.swift` Top Bar Quick Model Switcher**:
   - In `compactTopBar`, populate the Switch Model menu using `store.availableChatModels` (which guarantees readiness via `isReadyChatModel`).
   - Use standard SwiftUI `Label(model.catalogItem.displayName, systemImage: activeModel?.catalogItem.id == model.catalogItem.id ? "checkmark" : model.catalogItem.runtimeType.icon)`.
   - On model selection:
     ```swift
     store.setDefaultModel(id: model.catalogItem.id)
     Task {
         await RuntimeMemoryCoordinator.prepareForRuntime(model.catalogItem.runtimeType)
     }
     ```
   - Add `.disabled(isSending)` to guard against switching mid-generation.
3. **`ModelLibraryView.swift`**:
   - Dynamic "Best for your iPhone" match badge:
     * In `ModelTile` and model cards, when `item.isBestMatch(for: DeviceTier.current())`, render a prominent cyan capsule badge: `Label("Best for your iPhone", systemImage: "sparkles")` with AppTheme styling.
   - Dedicated "Vision & Camera Ready" shelf:
     * In `body` (when no search query is active), add `visionReadySection` horizontal scroll carousel showcasing VLM models (`tierFilteredCatalog.filter { $0.supportsVision || $0.inputModes.contains(.image) }`).
   - Update `capabilityFilterBar` vision toggle:
     * Change label to `"Vision & Camera"` with icon `"camera.viewfinder"`.
4. **Unit Tests**:
   - Add unit tests verifying `isBestMatch(for:)` across Compact, Standard, Pro, and Ultra tiers in `ModelCatalogItemTests.swift`.
5. **Run Verification & Tests**:
   - Run `xcodegen generate`.
   - Run `xcodebuild test` for `ModelCatalogItemTests`, `CatalogConsistencyTests`, and app tests:
     ```bash
     xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/WorkerM3DerivedData -only-testing EdgeMindAiTests/ModelCatalogItemTests -only-testing EdgeMindAiTests/CatalogConsistencyTests
     ```
   - Ensure all tests pass with 0 failures.
6. Write your handoff report to `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai/.agents/worker_m3/handoff.md` and report completion.
