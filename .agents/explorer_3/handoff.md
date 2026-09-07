# Handoff Report: R3 — Usability & Discovery Highlights

**Author**: Explorer 3  
**Role**: teamwork_preview_explorer  
**Scope**: R3 — Usability & Discovery Highlights for EdgeMind AI  
**Type**: Hard Handoff (Complete)  
**Date**: 2026-09-07T04:54:00Z  

---

## 1. Observation

### 1.1 `ChatView.swift` Top Bar & Model Switcher
1. **Top Bar Hierarchy**:
   - In `EdgeMindAi/Features/Chat/ChatView.swift`, lines 358–359:
     ```swift
     .navigationBarTitleDisplayMode(.inline)
     .toolbar(.hidden, for: .navigationBar)
     ```
   - Top bar UI is rendered via `compactTopBar` (lines 444–551).
2. **Current Model Switcher Implementation**:
   - In `EdgeMindAi/Features/Chat/ChatView.swift`, lines 464–484:
     ```swift
     let installedChatModels = store.installedModels.filter {
         $0.catalogItem.primaryUse == .chat && $0.installState == .installed
     }
     Menu {
         if !installedChatModels.isEmpty {
             Section("Switch Model") {
                 ForEach(installedChatModels) { model in
                     Button {
                         store.setDefaultModel(id: model.catalogItem.id)
                         prewarmSelectedModel()
                     } label: {
                         HStack {
                             Text(model.catalogItem.displayName)
                             if activeModel?.catalogItem.id == model.catalogItem.id {
                                 Image(systemName: "checkmark")
                             }
                         }
                     }
                 }
             }
         }
         Button {
             showModelPicker = true
         } label: {
             Label("All Models & Downloads…", systemImage: "square.stack.3d.up")
         }
     }
     ```
3. **Filtering Discrepancy**:
   - `store.installedModels.filter { ... }` does not verify file existence on disk or runtime support on the current host.
   - `EdgeMindAi/State/AppStateStore.swift` defines `store.availableChatModels` (line 88) using `isReadyChatModel(_:)` (lines 548–575). On the iOS Simulator, `isReadyChatModel` explicitly returns `false` for MLX models (lines 563–565).
   - In `AppStateStore.swift` line 92:
     ```swift
     func setDefaultModel(id: UUID) {
         guard installedModels.contains(where: { $0.catalogItem.id == id && isReadyChatModel($0) }) else {
             return
         }
     ```
     Attempting to select a model that fails `isReadyChatModel` silently fails without updating `defaultModel`.
4. **Runtime Eviction on Model Switch**:
   - `prewarmSelectedModel()` in `ChatView.swift` lines 230–237 only handles GGUF:
     ```swift
     guard let model = store.defaultModel, model.catalogItem.runtimeType == .gguf else {
         return
     }
     ```
   - When switching to MLX, LiteRT-LM, or Apple Foundation Models, `RuntimeMemoryCoordinator.prepareForRuntime(_:)` is NOT called at switch time, delaying eviction of the previous runtime until `sendPrompt()` is triggered (line 1922).
5. **SwiftUI Menu Labels**:
   - Using `HStack` inside `Button` within a `Menu` (lines 475–480) violates standard iOS menu item rendering. SwiftUI menus require `Label(title, systemImage:)` to display an icon or checkmark properly.

### 1.2 `ModelLibraryView.swift` Hardware Badge & Vision Shelf
1. **Static iPhone Badge**:
   - In `EdgeMindAi/Features/Models/ModelLibraryView.swift`, lines 1759–1771:
     ```swift
     if item.recommendedForIPhone {
         HStack(spacing: 4) {
             Image(systemName: "iphone")
                 .font(.system(size: 9, weight: .bold))
             Text("iPhone")
                 .font(.system(size: 10, weight: .bold, design: .rounded))
         }
         .foregroundStyle(AppTheme.success)
         .padding(.horizontal, 8)
         .padding(.vertical, 5)
         .background(AppTheme.success.opacity(0.12))
         .clipShape(Capsule())
     }
     ```
   - The badge is completely static, based solely on `item.recommendedForIPhone`, without considering `DeviceTier.current()`.
2. **Missing Vision Shelf**:
   - In `ModelLibraryView.swift`, lines 43–54:
     ```swift
     if hasActiveQuery {
         searchResultsSection
     } else {
         if !installedModels.isEmpty {
             installedSection
         } else {
             noInstalledModelsHint
         }

         familyDirectorySection
     }
     ```
   - There is no shelf for vision models. Vision models are scattered across `familyDirectorySection`.
3. **Filter Bar**:
   - In `ModelLibraryView.swift`, lines 848–854, the vision filter toggle is labeled simply `"Vision"` with icon `"eye.fill"`.
4. **VLM Models in Catalog**:
   - In `EdgeMindAi/State/MockCatalogData.swift`:
     - Gemma 4 E2B Instruct (LiteRT-LM): line 50, `supportsVision: true`, `inputModes: [.text, .image, .document]`.
     - Qwen 3.5 VL 0.8B Instruct (MLX): line 210, `supportsVision: true`, `inputModes: [.text, .image, .document]`.
     - Liquid LFM 2.5 VL 1.6B (MLX): line 320, `supportsVision: true`, `inputModes: [.text, .image, .document]`.
     - SmolVLM2 500M Instruct (MLX): line 465, `supportsVision: true`, `inputModes: [.text, .image, .document]`.
     - SmolVLM2 2.2B Instruct (MLX): line 505, `supportsVision: true`, `inputModes: [.text, .image, .document]`.
     - Qwen 3.5 VL 4B Instruct (MLX): line 805, `supportsVision: true`, `inputModes: [.text, .image, .document]`.

### 1.3 Project Build & Test Failure
- Running `xcodebuild test` resulted in:
  ```
  Testing failed:
      Cannot find 'AvailableMemoryGuard' in scope
  ```
- Command: `xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -destination 'id=EB4F7FE3-8541-4B9E-AFC1-2AD5C346FB8F' -derivedDataPath build/SimulatorDerivedData -only-testing EdgeMindAiTests/DeviceTierTests`
- File `EdgeMindAi/Services/Inference/AvailableMemoryGuard.swift` exists on disk (added for R1) but is not registered in `EdgeMindAi.xcodeproj/project.pbxproj` because `xcodegen generate` has not been run since the file was created.

---

## 2. Logic Chain

1. **Top Bar Quick Switcher**:
   - *From Observation 1.1.3*: `store.setDefaultModel(id:)` rejects any model failing `isReadyChatModel`.
   - *From Observation 1.1.2*: `compactTopBar` currently populates from `store.installedModels`, which includes unready/unsupported models.
   - *Inference*: The Quick Switcher must source its options from `store.availableChatModels`.
   - *From Observation 1.1.4*: Switching to non-GGUF models does not trigger `RuntimeMemoryCoordinator.prepareForRuntime`.
   - *Inference*: The switcher button action must dispatch `RuntimeMemoryCoordinator.prepareForRuntime(model.catalogItem.runtimeType)` inside a `Task` to immediately evict old runtime weights upon switching.
   - *From Observation 1.1.5*: Using `Label(model.catalogItem.displayName, systemImage: activeModel?.catalogItem.id == model.catalogItem.id ? "checkmark" : model.catalogItem.runtimeType.icon)` conforms to standard iOS menu appearance.

2. **Dynamic Hardware Recommendation Badge ("Best for your iPhone")**:
   - *From Observation 1.2.1*: The current `"iPhone"` badge is static and does not account for `DeviceTier.current()`.
   - *From Observation 1.1.1*: Compact devices have 1.2 GB usable weight; Standard devices have 2.2 GB; Pro devices have 4.5 GB.
   - *From Observation 1.2.4*: Models have `minimumTier`, `estimatedResidentGB(contextTokens:)`, and `auditVerdict`.
   - *Inference*: A model qualifies as "Best for your iPhone" when:
     - `item.minimumTier <= currentTier`
     - `item.estimatedResidentGB(contextTokens: currentTier.safeContextTokens) <= currentTier.usableWeightGB`
     - `!item.auditVerdict.isRed`
     - Fits tier-specific sweet spots (e.g. <=1.2 GB for Compact, 1B–2B for Standard, 2B–4B/VLM for Pro).
   - *Inference*: Adding `func isBestMatch(for tier: DeviceTier) -> Bool` on `ModelCatalogItem` provides a centralized, unit-testable decision function that drives the badge in `ModelTile` and shelf cards.

3. **Dedicated "Vision & Camera Ready" Shelf & Filter**:
   - *From Observation 1.2.2 & 1.2.4*: Six 2026 VLM models exist in the catalog with `supportsVision: true` and `.image` in `inputModes`.
   - *From Observation 1.2.2*: Without a query, `ModelLibraryView` currently shows only `installedSection` and `familyDirectorySection`.
   - *Inference*: Adding a horizontal carousel shelf (`visionReadySection`) populated by `visionReadyModels` (`tierFilteredCatalog.filter { $0.supportsVision || $0.inputModes.contains(.image) }`) and updating the filter bar button to `"Vision & Camera"` directly fulfills R3.

4. **Build Issue Resolution**:
   - *From Observation 1.3*: `AvailableMemoryGuard.swift` is missing from `project.pbxproj`.
   - *Inference*: `xcodegen generate` must be run to synchronize `EdgeMindAi.xcodeproj` with the filesystem.

---

## 3. Caveats

1. **Simulator Execution Restrictions**:
   - MLX and LiteRT-LM runtime execution are disabled on the iOS Simulator (`#if targetEnvironment(simulator)`).
   - In simulator testing, only GGUF and Apple Foundation Models execute. However, `isBestMatch(for:)`, model library browsing, shelves, and UI menus can all be fully validated on the simulator.
2. **Read-Only Explorer Scope**:
   - In accordance with team explorer rules, no source files outside `.agents/explorer_3/` were modified. All proposed changes are documented as blueprints in `analysis.md` and this handoff.
3. **Dependency on XcodeGen**:
   - Running tests requires executing `xcodegen generate` to include `AvailableMemoryGuard.swift` in the Xcode project.

---

## 4. Conclusion

The path to fully implement and verify R3 (Usability & Discovery Highlights) is clear and well-defined:
1. **`ChatView.swift`**:
   - Replace `store.installedModels` with `store.availableChatModels` in `compactTopBar`.
   - Use `Label(model.catalogItem.displayName, systemImage: ...)` for menu items.
   - Dispatch `RuntimeMemoryCoordinator.prepareForRuntime(...)` upon switching.
   - Apply `.disabled(isSending)` and accessibility labels.
2. **`ModelCatalogItem.swift`**:
   - Implement `func isBestMatch(for tier: DeviceTier) -> Bool`.
3. **`ModelLibraryView.swift`**:
   - Display the "Best for your iPhone" dynamic match badge on `ModelTile` and shelf cards.
   - Add `visionReadySection` horizontal scroll shelf.
   - Update `capabilityFilterBar` to `"Vision & Camera"`.
4. **`EdgeMindAiTests`**:
   - Add tests for `isBestMatch(for:)`, `availableChatModels`, and vision catalog consistency.

---

## 5. Verification Method

### 5.1 Project Regeneration Command
```bash
xcodegen generate
```

### 5.2 Unit Test Commands
To verify model catalog items and hardware tier matching:
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=LocalAI iPhone 17 Pro' \
  -derivedDataPath build/SimulatorDerivedData \
  -only-testing EdgeMindAiTests/ModelCatalogItemTests
```

To verify AppStateStore and catalog consistency:
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=LocalAI iPhone 17 Pro' \
  -derivedDataPath build/SimulatorDerivedData \
  -only-testing EdgeMindAiTests/AppStateStoreMigrationTests \
  -only-testing EdgeMindAiTests/CatalogConsistencyTests
```

To run all unit tests:
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=LocalAI iPhone 17 Pro' \
  -derivedDataPath build/SimulatorDerivedData
```

### 5.3 Code Inspection & Invalidation Conditions
- **Files to Inspect**:
  - `EdgeMindAi/Features/Chat/ChatView.swift` (`compactTopBar` menu implementation)
  - `EdgeMindAi/Features/Models/ModelLibraryView.swift` (`visionReadySection`, `visionShelfCard`, `ModelTile.capabilityRow`)
  - `EdgeMindAi/Models/ModelCatalogItem.swift` (`isBestMatch(for:)`)
- **Invalidation Conditions**:
  - If a model with `auditVerdict == .red` displays the "Best for your iPhone" badge, the logic is invalid.
  - If a model requiring `.pro` tier (8 GB) displays "Best for your iPhone" on a `.compact` device, the logic is invalid.
  - If switching models in `compactTopBar` leaves previous runtime weights in memory, R1 mutual exclusion is violated.
  - If `store.availableChatModels` is bypassed in favor of raw `installedModels`, unready models will appear in the Quick Switcher.
