# Technical Analysis: R3 — Usability & Discovery Highlights

**Author**: Explorer 3 (Teamwork Explorer)  
**Date**: 2026-09-07T04:52:00Z  
**Scope**: R3 — Usability & Discovery Highlights for EdgeMind AI  
**Files Investigated**:
- `EdgeMindAi/Features/Chat/ChatView.swift`
- `EdgeMindAi/Features/Models/ModelLibraryView.swift`
- `EdgeMindAi/State/AppStateStore.swift`
- `EdgeMindAi/Models/ModelCatalogItem.swift`
- `EdgeMindAi/Models/InstalledModel.swift`
- `EdgeMindAi/Models/ChatSession.swift`
- `EdgeMindAi/Services/Inference/DeviceTier.swift`
- `EdgeMindAi/Services/Inference/RuntimeMemoryCoordinator.swift`
- `EdgeMindAi/State/MockCatalogData.swift`
- `EdgeMindAiTests/ModelCatalogItemTests.swift`
- `EdgeMindAiTests/DeviceTierTests.swift`
- `EdgeMindAiTests/AppStateStoreMigrationTests.swift`
- `EdgeMindAiTests/CatalogConsistencyTests.swift`

---

## 1. Executive Summary

Requirement R3 of the EdgeMind AI modernization focuses on elevating on-device user experience across two primary surfaces:
1. **Chat Top Bar Quick Model Switcher (`ChatView.swift`)**: Enabling users to seamlessly switch between installed, ready-to-run models directly from the chat header without navigating away to the model management screen, while strictly coordinating runtime memory eviction.
2. **Dynamic Hardware Recommendations ("Best for your iPhone") (`ModelLibraryView.swift`)**: Intelligently highlighting optimal models for the user's detected hardware tier (`DeviceTier.current()`) using memory budget math, tier constraints, and audit verdicts.
3. **Dedicated "Vision & Camera Ready" Shelf & Filter (`ModelLibraryView.swift`)**: Surfacing the premier 2026 vision-language lineup (Gemma 4 E2B LiteRT-LM, Qwen 3.5 VL 0.8B/4B MLX, Liquid LFM 2.5 VL 1.6B MLX, SmolVLM2 500M/2.2B MLX) through a dedicated horizontal carousel and an enhanced filter bar.

This investigation establishes the complete architectural blueprints, data dependencies, UI component designs, failure modes, and automated test specifications necessary to implement R3.

---

## 2. Problem Statement & Acceptance Criteria

### Problem Statement
- In `ChatView.swift`, switching models previously required opening a modal sheet (`modelPickerSheet`) or switching tabs. While an initial menu prototype exists in `compactTopBar`, it uses raw `store.installedModels` (which can include models unready to run or incompatible with the current environment, such as MLX on the simulator), renders plain buttons without proper checkmark semantics or runtime icons, does not evict previous non-GGUF runtimes upon switching, and lacks accessibility metadata.
- In `ModelLibraryView.swift`, model cards show a static `"iPhone"` badge based solely on `item.recommendedForIPhone`, completely ignoring whether the user is holding an iPhone 12 (Compact 4 GB), an iPhone 15 (Standard 6 GB), or an iPhone 16 Pro (Pro 8 GB). A 4B model will show "iPhone" even on a 4 GB device that will crash or Jetsam.
- In `ModelLibraryView.swift`, vision models that accept camera and photo input are scattered across disparate families in the directory list. There is no curated "shelf" (horizontal carousel) showcasing vision models, and the filter bar toggle is labeled generically as "Vision".

### R3 Acceptance Criteria (from `ORIGINAL_REQUEST.md`)
- [x] Quick Model Switcher menu functions directly from the Chat top bar.
- [x] "Best for your iPhone" dynamic match badge recommends optimal models tailored to `DeviceTier.current()`.
- [x] Dedicated "Vision & Camera Ready" filter and shelf in `ModelLibraryView.swift` highlighting models that accept image attachments (`supportsVision` / `inputModes.contains(.image)`).

---

## 3. Deep Dive: `ChatView.swift` Top Navigation Bar & Quick Model Switcher

### 3.1 Existing Navigation Hierarchy
In `ChatView.swift` (lines 358-360), standard navigation bars are hidden in favor of a custom, streamlined top bar:
```swift
.navigationBarTitleDisplayMode(.inline)
.toolbar(.hidden, for: .navigationBar)
```
The active top bar is `compactTopBar` (lines 444-551), laid out as an `HStack`:
- **Leading**: Button toggling `store.isSidebarOpen` (Chat History drawer).
- **Center**: Centered model switcher button/menu displaying active model display name and chevron.
- **Trailing**: Session actions (Delete current chat confirmation button if session exists, New Chat `+` button).

### 3.2 Analysis of Current Quick-Switcher Implementation
Lines 463-510 currently contain:
```swift
// Model Picker (Centered Quick-Switcher)
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
} label: {
    HStack(spacing: 5) {
        Text(activeModel?.catalogItem.displayName ?? "Select Model")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(AppTheme.textTertiary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
        Capsule()
            .fill(AppTheme.controlFill)
    )
}
.buttonStyle(.plain)
```

### 3.3 Flaws & Required Improvements in `ChatView.swift`

1. **Source Model Collection**:
   - `store.installedModels.filter { $0.catalogItem.primaryUse == .chat && $0.installState == .installed }` does not verify if the model file is actually present on disk or if the runtime is supported on the current device.
   - `AppStateStore` provides `store.availableChatModels`, which calls `isReadyChatModel(_:)`. For GGUF and LiteRT, this validates `fileURL` existence on disk. For MLX, it verifies `!targetEnvironment(simulator)`.
   - If an invalid model is in `installedModels`, `store.setDefaultModel(id:)` silently rejects it (guard line 92 in `AppStateStore.swift`), leaving the UI unresponsive to the user's tap.
   - **Resolution**: Use `store.availableChatModels`.

2. **SwiftUI Menu Item Representation**:
   - In SwiftUI, an `HStack` inside a `Button` within a `Menu` is not standard iOS menu styling and causes checkmarks to disappear or align inconsistently across iOS versions.
   - The idiomatic SwiftUI approach for menu items is `Label(title, systemImage:)`:
     ```swift
     Label(
         model.catalogItem.displayName,
         systemImage: activeModel?.catalogItem.id == model.catalogItem.id ? "checkmark" : model.catalogItem.runtimeType.icon
     )
     ```

3. **Runtime Switching & Memory Eviction**:
   - `prewarmSelectedModel()` (lines 230-254) has an early exit:
     `guard let model = store.defaultModel, model.catalogItem.runtimeType == .gguf else { return }`
   - When switching from GGUF to MLX, LiteRT-LM, or Apple Foundation Models, `prewarmSelectedModel()` does nothing. It does NOT call `RuntimeMemoryCoordinator.prepareForRuntime(...)`.
   - Consequently, the previous runtime's weights and KV cache remain resident in memory until the user sends their first message!
   - **Resolution**: Proactively execute `RuntimeMemoryCoordinator.prepareForRuntime(model.catalogItem.runtimeType)` inside a `Task` when switching to any model, satisfying R1 mutual exclusion immediately upon user selection.

4. **In-Flight Generation Safety**:
   - Switching models while `isSending == true` would create a race condition where the active generation stream could be orphaned or memory evicted out from under the active runtime.
   - **Resolution**: Apply `.disabled(isSending)` to the Quick Switcher `Menu`, or opacity change to visually indicate disabled state during inference.

5. **Accessibility**:
   - Add `.accessibilityLabel("Active model: \(activeModel?.catalogItem.displayName ?? "No model selected"). Quick model switcher")`
   - Add `.accessibilityHint("Double-tap to switch between installed models or open model library")`

---

## 4. Deep Dive: `ModelLibraryView.swift` & Hardware Match Badge

### 4.1 Hardware Detection Baseline
Hardware classification is governed by `DeviceTier.swift`:
- `DeviceTier.current()` inspects `DeviceCapabilityService.machineModel()` and `ProcessInfo.processInfo.physicalMemory`.
- Tiers and budgets:
  | Tier | RAM Range | Safe Context | Usable Weight | Jetsam Soft Limit | Representative Devices |
  |---|---|---|---|---|---|
  | **Compact** | 3–4 GB | 2,048 tok | 1.2 GB | 1.2 GB | iPhone 10, 11, 12 series, 13 mini, SE 2/3 |
  | **Standard** | 6 GB | 4,096 tok | 2.2 GB | 2.2 GB | iPhone 13, 14, 15 non-Pro |
  | **Pro** | 8 GB | 8,192 tok | 4.5 GB | 4.5 GB | iPhone 15 Pro, 16, 17 series |
  | **Ultra** | 12 GB+ | 16,384 tok | 7.0 GB | 7.0 GB | iPhone 17 Pro Max, M-series iPads |

### 4.2 Formulating the "Best for your iPhone" Dynamic Match Rule
The badge must dynamically adapt to the user's detected hardware tier:
- **Compact Tier (4 GB)**:
  - Memory ceiling is very tight (usable weight: 1.2 GB).
  - Models must have `minimumTier == .compact`.
  - `estimatedResidentGB(contextTokens: 2048) <= 1.2`.
  - Must not be red-verdicted (`!item.auditVerdict.isRed`).
  - `item.recommendedForIPhone == true` or `runtimeStatus == .recommended`.
  - Examples: Qwen 3 0.6B (MLX/GGUF), Liquid LFM 2.5 350M, Qwen 3.5 0.8B, SmolLM 360M.
- **Standard Tier (6 GB)**:
  - Usable weight is 2.2 GB.
  - Models must have `minimumTier <= .standard`.
  - `estimatedResidentGB(contextTokens: 4096) <= 2.2`.
  - Examples: Qwen 3 1.7B / Qwen 3.5 2B, IBM Granite 3.3 2B, Liquid LFM 2.5 1.2B, DeepSeek R1 Distill Qwen 1.5B.
- **Pro Tier (8 GB)**:
  - Usable weight is 4.5 GB.
  - Models must have `minimumTier <= .pro`.
  - `estimatedResidentGB(contextTokens: 8192) <= 4.5`.
  - Examples: Apple Intelligence Foundation Models, Gemma 4 E2B Instruct (LiteRT-LM), Mistral Ministral 3 3B, Qwen 3.5 VL 0.8B/4B, LFM 2.5 VL 1.6B.
- **Ultra Tier (12 GB+)**:
  - Usable weight is 7.0 GB.
  - Large models with extended contexts (Qwen 3.5 VL 4B, Qwen 3 4B Thinking, full context reasoning models).

### 4.3 Proposed Method on `ModelCatalogItem`
In `ModelCatalogItem.swift`:
```swift
extension ModelCatalogItem {
    /// Determines whether this model is an optimal, recommended match for the
    /// user's specific detected hardware tier.
    func isBestMatch(for tier: DeviceTier) -> Bool {
        guard primaryUse == .chat else { return false }
        guard minimumTier <= tier else { return false }
        guard !auditVerdict.isRed else { return false }
        
        let residentGB = estimatedResidentGB(contextTokens: tier.safeContextTokens)
        guard residentGB <= tier.usableWeightGB else { return false }

        switch tier {
        case .compact:
            // Compact devices cannot tolerate 1.5B+ models safely.
            return minimumTier == .compact && (recommendedForIPhone || runtimeStatus == .recommended)
            
        case .standard:
            // Standard devices (6 GB) run 1B-2B models with full instruction following.
            return (minimumTier == .standard || minimumTier == .compact)
                && (recommendedForIPhone || runtimeStatus == .recommended)
            
        case .pro, .ultra:
            // Pro/Ultra devices (8-12 GB+) run premier 2026 edge & vision models.
            return (runtimeStatus == .recommended || auditVerdict.isGreen || recommendedForIPhone)
        }
    }
}
```

### 4.4 Badge Visual Design & Integration in `ModelTile`
In `ModelLibraryView.swift`, within `capabilityRow` (lines 1740-1786) and shelf cards:
```swift
if item.isBestMatch(for: currentTier) {
    HStack(spacing: 4) {
        Image(systemName: "sparkles")
            .font(.system(size: 9, weight: .bold))
        Text("Best for your iPhone")
            .font(.system(size: 10, weight: .bold, design: .rounded))
    }
    .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.95))
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(Color(red: 0.20, green: 0.78, blue: 0.95).opacity(0.14))
    .clipShape(Capsule())
}
```

---

## 5. Deep Dive: `ModelLibraryView.swift` & "Vision & Camera Ready" Shelf & Filter

### 5.1 September 2026 VLM Lineup
The updated September 2026 catalog features four key VLM model families:
1. **Google Gemma 4 E2B Instruct (LiteRT-LM)**: 2B params, LiteRT-LM INT4, native multimodal vision, Pro tier.
2. **Qwen 3.5 VL (0.8B / 4B MLX)**: High-efficiency vision-language reasoning, Standard & Pro tiers.
3. **Liquid AI LFM 2.5 VL 1.6B (MLX)**: Ultra-fast 1.6B vision model, Standard tier.
4. **SmolVLM2 (500M / 2.2B MLX)**: Compact, efficient edge vision models from Hugging Face.

Each item carries:
- `supportsVision: true`
- `sourceSupportsVision: true`
- `inputModes: [.text, .image, .document]`

### 5.2 The Dedicated "Vision & Camera Ready" Shelf
In `ModelLibraryView.swift`, when browsing the library without an active search query (`!hasActiveQuery`), a prominent shelf must showcase these models.

#### Shelf Data Source:
```swift
private var visionReadyModels: [ModelCatalogItem] {
    tierFilteredCatalog
        .filter { $0.supportsVision || $0.inputModes.contains(.image) }
        .sorted(by: sortModels)
}
```

#### Shelf Section Layout (`visionReadySection`):
```swift
private var visionReadySection: some View {
    Group {
        if !visionReadyModels.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader(
                        title: "Vision & Camera Ready",
                        subtitle: "Analyze photos, documents, and camera shots on-device."
                    )
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterVision = true
                        }
                    } label: {
                        Text("See all")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.capVision)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(visionReadyModels) { item in
                            visionShelfCard(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
```

#### Vision Shelf Card (`visionShelfCard`):
```swift
private func visionShelfCard(_ item: ModelCatalogItem) -> some View {
    let installed = installedModel(for: item)
    let isDefault = installed?.isDefault == true
    let isDownloading = activeDownloads.contains(item.id) || installed?.installState == .downloading

    return VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.capVision)
                    Text("Vision Ready")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.capVision)
                        .textCase(.uppercase)
                }

                Text(item.displayName)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: item.runtimeType.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(item.runtimeType == .mlx ? .orange : AppTheme.accent)
                .padding(8)
                .background((item.runtimeType == .mlx ? Color.orange : AppTheme.accent).opacity(0.12))
                .clipShape(Circle())
        }

        Text(item.summary)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(2)

        HStack(spacing: 6) {
            if item.isBestMatch(for: DeviceTier.current()) {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                    Text("Best Match")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.95))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(red: 0.20, green: 0.78, blue: 0.95).opacity(0.14))
                .clipShape(Capsule())
            }

            detailBadge(text: item.parameterSize, color: AppTheme.textSecondary)
            detailBadge(text: item.runtimeType.label, color: item.runtimeType == .mlx ? .orange : AppTheme.accent)
        }

        Spacer(minLength: 0)

        // Action button
        if installed?.installState == .installed {
            Button {
                store.setDefaultModel(id: item.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                    Text(isDefault ? "Default" : "Use for chat")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isDefault ? AppTheme.success : AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background((isDefault ? AppTheme.success : AppTheme.accent).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if isDownloading {
            HStack(spacing: 6) {
                ProgressView(value: installed?.progress ?? 0)
                    .tint(AppTheme.warning)
                Text("Downloading")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.warning)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AppTheme.panelRaised.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Button {
                attemptInstall(for: item)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Get (\(item.diskSize))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(AppTheme.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    .padding(14)
    .frame(width: 240, height: 210)
    .background(AppTheme.panel)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(AppTheme.capVision.opacity(0.25), lineWidth: 0.8)
    )
}
```

### 5.3 Filter Bar Enhancement
In `capabilityFilterBar` (lines 845-857):
```swift
capToggle(
    label: "Vision & Camera",
    icon: "camera.viewfinder",
    isOn: $filterVision,
    color: AppTheme.capVision
)
```
And in `filteredCatalog` (lines 135-155):
```swift
if filterVision && !(item.supportsVision || item.inputModes.contains(.image)) {
    return false
}
```

---

## 6. State Layer & Build Dependencies

### 6.1 State Architecture
- `AppStateStore.swift`:
  - `defaultModel`: Source of truth for active model in `ChatView`.
  - `availableChatModels`: Filters `installedModels` using `isReadyChatModel(_:)`. Validates file presence on disk and runtime eligibility (excludes MLX in simulator).
  - `setDefaultModel(id: UUID)`: Sets default model, updates persistence in UserDefaults.
- `ChatSession.swift`:
  - `let modelID: UUID?`: Stored per session. Note that `ChatView` inference uses `store.defaultModel`. When a user switches models via the Quick Switcher, subsequent messages in that chat run on the newly selected active model.

### 6.2 Build System & Project Configuration Alert
- **Build Issue Identified**: During test compilation, `SwiftCompile` failed with:
  `Cannot find 'AvailableMemoryGuard' in scope`
- **Root Cause**: `AvailableMemoryGuard.swift` was added to `EdgeMindAi/Services/Inference/` as part of R1, but has not yet been incorporated into `EdgeMindAi.xcodeproj/project.pbxproj`.
- **Prescribed Action**: Run `xcodegen generate` in project root whenever files are added to `EdgeMindAi/` to regenerate `EdgeMindAi.xcodeproj`.
- Note: As an Explorer agent with read-only constraints, Explorer 3 documents this finding for the orchestrator and implementer without directly modifying source outside `.agents/explorer_3`.

---

## 7. Automated Test Plan & Coverage Blueprint

### 7.1 Unit Tests for "Best for your iPhone" (`ModelCatalogItemTests.swift`)
```swift
func test_isBestMatch_compactTier() {
    let compactItem = ModelCatalogItem(
        displayName: "Qwen 3 0.6B (MLX)",
        family: .qwen,
        variant: "4-bit MLX",
        summary: "",
        parameterSize: "0.6B",
        quantization: "MLX 4-bit",
        diskSize: "~600 MB",
        contextWindow: "40K",
        runtimeType: .mlx,
        mlxModelID: "mlx-community/Qwen3-0.6B-4bit",
        recommendedForIPhone: true,
        minimumTier: .compact,
        runtimeStatus: .recommended,
        auditVerdict: .green
    )
    let proItem = ModelCatalogItem(
        displayName: "Qwen 3.5 VL 4B (MLX)",
        family: .qwen,
        variant: "4-bit MLX",
        summary: "",
        parameterSize: "4B",
        quantization: "MLX 4-bit",
        diskSize: "~2.8 GB",
        contextWindow: "32K",
        runtimeType: .mlx,
        mlxModelID: "mlx-community/Qwen3.5-VL-4B-4bit",
        supportsVision: true,
        recommendedForIPhone: false,
        minimumTier: .pro,
        runtimeStatus: .recommended,
        auditVerdict: .green
    )

    XCTAssertTrue(compactItem.isBestMatch(for: .compact), "0.6B compact model must be best match on compact tier")
    XCTAssertFalse(proItem.isBestMatch(for: .compact), "4B pro model must NOT be best match on compact tier")
}

func test_isBestMatch_redVerdictIsNeverBestMatch() {
    let redItem = ModelCatalogItem(
        displayName: "Faulty 1B",
        family: .qwen,
        variant: "4-bit MLX",
        summary: "",
        parameterSize: "1B",
        quantization: "MLX 4-bit",
        diskSize: "800 MB",
        contextWindow: "40K",
        runtimeType: .mlx,
        mlxModelID: "mlx-community/faulty",
        recommendedForIPhone: true,
        minimumTier: .compact,
        runtimeStatus: .worksWithWarnings,
        auditVerdict: .red("Severe crash during narrative test")
    )
    XCTAssertFalse(redItem.isBestMatch(for: .compact))
    XCTAssertFalse(redItem.isBestMatch(for: .standard))
    XCTAssertFalse(redItem.isBestMatch(for: .pro))
}
```

### 7.2 Unit Tests for Vision Filter Consistency (`CatalogConsistencyTests.swift`)
```swift
func test_visionReadyShelfContainsAllSupportedVLMs() {
    let visionModels = MockCatalogData.items.filter { $0.supportsVision || $0.inputModes.contains(.image) }
    XCTAssertGreaterThanOrEqual(visionModels.count, 4, "Must have at least 4 vision-language models cataloged")
    for model in visionModels {
        XCTAssertTrue(model.inputModes.contains(.image), "\(model.displayName) must contain .image input mode")
        XCTAssertTrue(model.sourceSupportsVision, "\(model.displayName) must have sourceSupportsVision set to true")
    }
}
```

### 7.3 Unit Tests for Quick Model Switcher (`AppStateStoreMigrationTests.swift`)
```swift
@MainActor
func test_availableChatModels_onlyReturnsReadyChatModels() {
    let store = AppStateStore(chatSessions: [], settings: .default)
    let models = store.availableChatModels
    for model in models {
        XCTAssertEqual(model.catalogItem.primaryUse, .chat)
        XCTAssertEqual(model.installState, .installed)
    }
}

@MainActor
func test_setDefaultModel_updatesAndPersists() {
    let store = AppStateStore(chatSessions: [], settings: .default)
    guard let systemModel = store.availableChatModels.first else { return }
    store.setDefaultModel(id: systemModel.catalogItem.id)
    XCTAssertEqual(store.defaultModel?.catalogItem.id, systemModel.catalogItem.id)
    XCTAssertEqual(store.settings.defaultModelID, systemModel.catalogItem.id)
}
```

---

## 8. Implementation Blueprint

### File Modification Targets
1. `EdgeMindAi/Models/ModelCatalogItem.swift`:
   - Add `func isBestMatch(for tier: DeviceTier) -> Bool`.
2. `EdgeMindAi/Features/Chat/ChatView.swift`:
   - Refactor `compactTopBar` model picker `Menu` to:
     - Use `store.availableChatModels`.
     - Use SwiftUI `Label(model.catalogItem.displayName, systemImage: ...)`.
     - Dispatch `RuntimeMemoryCoordinator.prepareForRuntime(model.catalogItem.runtimeType)` on switch.
     - Add `.disabled(isSending)` and comprehensive accessibility traits.
3. `EdgeMindAi/Features/Models/ModelLibraryView.swift`:
   - Add `visionReadyModels` computed property.
   - Add `visionReadySection` horizontal scroll shelf with `visionShelfCard(_:)`.
   - Update `capabilityFilterBar` button label to `"Vision & Camera"` with icon `"camera.viewfinder"`.
   - In `ModelTile`, add "Best for your iPhone" dynamic match badge using `item.isBestMatch(for: currentTier)`.
   - In `visionShelfCard`, include the "Best Match" badge.
4. `EdgeMindAiTests/ModelCatalogItemTests.swift`:
   - Add `test_isBestMatch_compactTier`, `test_isBestMatch_standardTier`, `test_isBestMatch_proTier`, `test_isBestMatch_redVerdictIsNeverBestMatch`.
5. `EdgeMindAiTests/AppStateStoreMigrationTests.swift`:
   - Add `test_availableChatModels_onlyReturnsReadyChatModels` and `test_setDefaultModel_updatesAndPersists`.

---

## 9. Conclusion
All components of R3 (Quick Model Switcher, "Best for your iPhone" dynamic match badge, and "Vision & Camera Ready" filter/shelf) have clear architectural paths, established design patterns in the codebase, and explicit validation criteria. The implementation requires no breaking schema changes and integrates smoothly with existing state management and memory coordination primitives.
