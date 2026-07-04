# MLX Stabilization and Device Tiering — Design

- **Date:** 2026-04-19
- **Branch:** `codex/stabilize-local-edge-app`
- **Scope:** Phase 1 of a two-phase app revamp. Phase 1 stabilizes MLX-on-device inference across all catalog models; Phase 2 (out of scope here) redesigns the UI.
- **Non-goals:** UI redesign, new models, GGUF path changes, voice / STT / auth / web-search architecture changes.

## 1. Problem

The app ships eight MLX catalog entries (6× Qwen 3, 2× LFM 2.5). In-field behavior today exhibits the following failures across subsets of those models, with no systematic way to detect or prevent them:

- **A.** Empty responses / hangs — model load succeeds but stream produces nothing.
- **B.** Garbage / repetition / mid-sentence truncation.
- **C.** Raw tokens leaking into the UI: `<|im_end|>`, `<think>`, `<|channel>thought`, `[INST]`, etc.
- **D.** Crashes / OOM on device for large models on low-RAM iPhones.
- **E.** Thinking / reasoning blocks rendering as plain text rather than the collapsible "Thinking…" section.
- **F.** Tool-calling models never emitting `<tool_call>`; they ramble instead.
- **G.** Vision models failing or ignoring the attached image.
- **H.** No repeatable audit across the full catalog.

Root causes:

1. **Catalog flags are aspirational.** `ModelCatalogItem` mirrors upstream model-card claims; `ChatView` treats them as runtime truth.
2. **Device tiering is minimal.** `DeviceCapabilityService` returns an n_ctx value but no RAM-tier → safe-model-set mapping, so a 4 GB iPhone can install Qwen 3 8B (5.5 GB).
3. **`StreamProcessor` tag set is incomplete** and the sanitizer runs post-stream only, so end-of-turn tokens flicker in the UI.
4. **No reproducible smoke test** exists for the full catalog; regressions ship silently.

## 2. Goals

- Every MLX model in the catalog is either **green-verified** by an automated audit or **explicitly hidden / flagged** on devices where it cannot run.
- Adding a future model to the catalog is a low-ceremony action that *must* pass the same audit before it ships as verified.
- The app's runtime behavior (think-block parsing, tool-call loop, image attachment) is driven by **verified capabilities**, not upstream claims.
- Every supported iPhone from A14 through A18 Pro gets at least one green-verified model that fits in memory, with clear messaging when a larger model is unavailable on the user's hardware.

## 3. Architecture overview

Five additive components. No rewrites of `MLXInferenceService`, `MLXRuntime`, `LocalLlamaInferenceService`, or `ChatView` structure.

```
┌─────────────────────────────────────────────────────────────┐
│ Settings → Developer (5-tap gate) → Model Diagnostics       │
│                       │                                      │
│                       ▼                                      │
│              ModelAuditRunner                                │
│                (orchestrator)                                │
│         │          │          │           │                 │
│         ▼          ▼          ▼           ▼                 │
│   DeviceTier  RuntimeProfile  AuditCase  AuditReport        │
└─────────────────────────────────────────────────────────────┘
        │              │             │
        ▼              ▼             ▼
  ModelCatalogItem  StreamProcessor  MLXInferenceService
  (filter by tier)  (+ new tags)     (existing — untouched)
```

### 3.1 Components

| Component | Purpose | Location |
|-----------|---------|----------|
| `DeviceTier` | Classify device into `.compact` / `.standard` / `.pro` / `.ultra` based on `hw.machine`. | `Services/Inference/DeviceCapabilityService.swift` |
| `RuntimeProfile` | Per-model, app-verified capability sheet. JSON-backed. Source of truth for runtime behavior. | `Services/Inference/RuntimeProfile.swift` + `Resources/RuntimeProfiles.json` |
| `ModelAuditRunner` | Pure service. Runs `AuditCase`s against installed models, emits `AuditProgress` events. | `Services/Inference/ModelAuditRunner.swift` |
| `AuditCase` + `AuditExpectations` | Describe one scripted test (prompt, optional image, expectations). | same file |
| `ModelDiagnosticsView` | Hidden Developer screen; drives the runner, shows live progress, exports/promotes reports. | `Features/Settings/ModelDiagnosticsView.swift` |

### 3.2 Runtime integration

- `ChatView` reads `RuntimeProfile`, not `ModelCatalogItem` flags, when deciding:
  - whether to route the stream through a think-block collapsible,
  - whether to inject tool definitions into the system prompt and run the agentic loop,
  - whether to allow image attachment.
- `ModelLibraryView` filters by `DeviceTier`, hiding `minimumTier > currentTier` by default with a "Show all" toggle.
- `ModelDownloadService` refuses downloads that exceed `DeviceTier.usableWeightGB` unless the user taps "I understand, download anyway."

## 4. DeviceTier

### 4.1 Classification

| Tier | Devices | Total RAM | Foreground budget | Safe MLX models |
|------|---------|-----------|-------------------|------------------|
| `.compact` | iPhone 12, 12 mini, 12 Pro, 12 Pro Max, 13 mini, SE 2, SE 3 | 4 GB | ~2.2 GB | Qwen 3 0.6B |
| `.standard` | iPhone 13, 13 Pro, 13 Pro Max, 14, 14 Plus, 14 Pro, 14 Pro Max, 15, 15 Plus | 6 GB | ~3.3 GB | `.compact` + Qwen 3 1.7B, LFM2.5 1.2B, LFM2.5-VL 1.6B |
| `.pro` | iPhone 15 Pro, 15 Pro Max, 16, 16 Plus, 16 Pro, 16 Pro Max, 17, 17 Pro | 8 GB | ~4.5 GB | `.standard` + Qwen 3 4B (all three 2507 variants) |
| `.ultra` | iPhone 17 Pro Max (12 GB), iPad Pro M-series | 12+ GB | ~7 GB | `.ultra` + Qwen 3 8B |

Budget formula: `usableWeightGB ≈ totalRAM × 0.35`. iOS jetsam foreground ceiling is ~55–60% of physical RAM; the 0.35 factor leaves room for KV cache, MLX GPU cache (512 MB LLM / 768 MB VLM), vision SigLIP tower, and app heap/OS overhead.

### 4.2 Catalog impact

- `ModelCatalogItem` gains `minimumTier: DeviceTier` (default `.standard`).
- `recommendedForIPhone` is **deprecated**. The `Codable` decoder is updated in the same commit: `recommendedForIPhone = try container.decodeIfPresent(Bool.self, forKey: .recommendedForIPhone) ?? false`. This is required because the current decoder at `ModelCatalogItem.swift:199` calls non-optional `decode(Bool.self, …)` — persisted `InstalledModel` records written before this field existed would fail to decode otherwise. New code reads `minimumTier`; `recommendedForIPhone` is retained as a read-only compatibility field and is not used for gating.
- Assignments for the current eight MLX entries:

| Model | `minimumTier` | Notes |
|-------|---------------|-------|
| Qwen 3 0.6B | `.compact` | Only `.compact`-safe model. |
| Qwen 3 1.7B | `.standard` | |
| Qwen 3 4B (base) | `.pro` | |
| Qwen 3 4B 2507 Instruct | `.pro` | |
| Qwen 3 4B 2507 Thinking | `.pro` | |
| Qwen 3 8B | `.ultra` | Hidden on everything below unless "Show all" toggled. |
| LFM2.5 1.2B Instruct | `.standard` | |
| LFM2.5-VL 1.6B | `.standard` | Tight on 6 GB with images; SigLIP tower pushes peak. |

### 4.3 Download guard

`ModelDownloadService.startDownload(_:)` calls `DeviceTier.guardDownload(_:)`. The guard uses a **resident-RAM estimator**, not raw disk size:

```
residentGB ≈ diskSizeGB × 1.15          // weights in memory (4-bit ≈ on-disk size, small overhead)
          + kvCacheGB(contextTokens)    // ≈ 2 × nLayers × nHeads × headDim × ctx × 2 bytes
          + (supportsVision ? 0.6 : 0)  // SigLIP tower + image tensors
          + 0.3                          // app heap + OS headroom
```

Guard fails with `DownloadError.exceedsDeviceBudget` if `residentGB > tier.usableWeightGB`. UI surfaces the guard with a modal: "This model needs approximately X GB of resident memory. Your device has budget for Y GB. It will likely crash. Proceed anyway?"

Positive confirmation persists a user-consent flag in `UserDefaults` under key `mlx.downloadConsent.<catalogID>` (`[UUID: Date]` dictionary) so subsequent downloads of the same model skip the prompt.

The estimator is a function on `ModelCatalogItem`: `estimatedResidentGB(contextTokens: Int) -> Double`. `contextTokens` defaults to the lesser of `catalog.contextWindowTokenCount` and `tier.safeContextTokens` (a new `DeviceTier` constant: 2048 / 4096 / 8192 / 16384).

## 5. RuntimeProfile

### 5.1 Schema

```swift
struct RuntimeProfile: Codable {
    let catalogID: UUID                      // ties to ModelCatalogItem.id
    let verifiedThinking: ThinkFormat?       // .none / .xmlThink / .qwenNative / .gemmaChannel
    let verifiedToolCalling: ToolCallFormat? // .none / .xmlToolCall / .gemmaNativeToolCall
    let verifiedVision: VisionMode           // .none / .textOnlyInputs / .imageAndText
    let knownLeakTokens: [String]
    let recommendedMaxTokens: Int
    let auditedAt: String                    // ISO-8601
    let auditVerdict: Verdict                // .green / .yellow(String) / .red(String)
}

enum ThinkFormat: String, Codable { case xmlThink, qwenNative, gemmaChannel }
enum ToolCallFormat: String, Codable { case xmlToolCall, gemmaNativeToolCall }
enum VisionMode: String, Codable { case none, textOnlyInputs, imageAndText }

enum Verdict: Codable {
    case green
    case yellow(String)
    case red(String)
}
```

### 5.2 Storage

- **Bundle source:** `LocalAIEdgeApp/Resources/RuntimeProfiles.json`. Checked into the repo. Hand-edited or promoted from an audit run.
- **Runtime read:** `RuntimeProfileStore` loads the bundled file once at launch and exposes `profile(for: UUID) -> RuntimeProfile?`. The override path is **Debug-only** and enforced at compile time:

  ```swift
  #if DEBUG
  private func loadOverride() -> [RuntimeProfile] { /* reads Documents/RuntimeProfiles.override.json */ }
  #else
  private func loadOverride() -> [RuntimeProfile] { [] }
  #endif
  ```

  This guarantees Release builds never honor an on-device override, preventing a malicious or broken override from flipping a `.red` verdict to `.green` in a shipped app.
- **Conflict resolution:** when Debug overrides exist, they shadow bundled entries by `catalogID`. `RuntimeProfileStore.diagnosticsSummary()` logs the shadow so devs see when an override is live.
- **Missing profile:** model runs in **safe minimum mode** — text-only, no tool-call loop, no think-block parsing, strict scrubber. This is the default for unprofiled newcomers.

### 5.3 Profile-over-catalog precedence

`ChatView` and `ModelLibraryView` use the resolver `ModelRuntimeResolver.resolve(catalog: item) -> ResolvedModel` which merges:

1. Prefer `profile.verifiedX` for runtime decisions (think, tool, vision gating).
2. Keep `catalog.supportsX` for *display* (card badges, model descriptions).
3. If they disagree, surface a neutral "Vision claimed — not verified in this app" footnote on the card.

### 5.4 Starting profile set

Ship all eight entries at `.yellow("pending-audit")` with the best-known starting shape:

| Model | Think | Tool | Vision |
|-------|-------|------|--------|
| Qwen 3 0.6B | `.qwenNative` | `.xmlToolCall` | `.none` |
| Qwen 3 1.7B | `.qwenNative` | `.xmlToolCall` | `.none` |
| Qwen 3 4B (base) | `.qwenNative` | `.xmlToolCall` | `.none` |
| Qwen 3 4B 2507 Instruct | `.none` *(not thinking)* | `.xmlToolCall` | `.none` |
| Qwen 3 4B 2507 Thinking | `.qwenNative` | `.xmlToolCall` | `.none` |
| Qwen 3 8B | `.qwenNative` | `.xmlToolCall` | `.none` |
| LFM2.5 1.2B Instruct | `.none` | `.xmlToolCall` | `.none` |
| LFM2.5-VL 1.6B | `.none` | `.xmlToolCall` *(text inputs only)* | `.imageAndText` |

Audit runner (Section 7) confirms or flips each cell. Green verdicts replace `.yellow` and are committed.

## 6. StreamProcessor fixes

### 6.1 Think-tag detection

| Format | Opens | Closes | Models |
|--------|-------|--------|--------|
| `.xmlThink` (existing) | `<think>` / `<thinking>` / `<reasoning>` | matching close | Qwen 3, LFM thinking variants |
| `.qwenNative` (new) | `<|im_start|>think` or `<|think|>` | `<|im_end|>` or `<|/think|>` | Qwen builds leaking native tokens |
| `.gemmaChannel` (new, future) | `<|channel>thought\n` | `<|channel>` or `<|end|>` | Gemma 4 (dead code today; ready when Gemma MLX lands) |

`StreamProcessor` activates detectors based on `RuntimeProfile.verifiedThinking`. If `.none`, think parsing is off and output flows straight through the scrubber. This makes non-thinking models deterministic.

### 6.2 Mid-stream token leak scrubber (fixes C)

A new actor `TokenLeakScrubber` inside `StreamProcessor`:

- Maintains a **lookahead buffer** of up to 24 characters.
- If a delta ends with a prefix that could be the start of a leak token (`<|`, `<e`, `[I`, `<|ch`, `<end`), holds the tail until the next token arrives or the stream ends.
- Scrubs known end-tokens: `<|im_end|>`, `<|endoftext|>`, `<end_of_turn>`, `[INST]`, `[/INST]`, `<|eot_id|>`, `<|im_start|>`, plus anything in `RuntimeProfile.knownLeakTokens`.
- Lookahead buffer is sized to `max(24, longestScrubTokenLength + 8)` so new entries in `knownLeakTokens` extend the buffer automatically instead of silently bypassing it.
- Yields only **clean** text forward. The existing post-stream `AssistantResponseSanitizer.clean()` is **kept** at the sink as defense-in-depth; if the scrubber misses a token at a boundary the sanitizer still catches it. Duplicate stripping is idempotent.

### 6.3 Hang watchdog (fixes A)

- Implemented with a `withTaskGroup` wrapper around the `for await token in rawStream` loop. One child task reads the stream; a sibling task sleeps for the timeout. Whichever finishes first cancels the other:

  ```swift
  await withTaskGroup(of: Event.self) { group in
      group.addTask { for await token in rawStream { … emit .token(token) }; return .streamEnded }
      group.addTask { try? await Task.sleep(for: .seconds(timeout)); return .timedOut }
      for await event in group {
          switch event {
          case .timedOut where !anyTokenReceived:
              // yield fallback + done, cancel group
          case .streamEnded:
              group.cancelAll(); return
          …
          }
      }
  }
  ```

- If **no tokens arrive within `AppSettings.inferenceV2Timeout`** (default 15s, loosened to 30s on `.compact`) after `ensureModel` returns, the processor yields `.textDelta("Model did not produce output.")` + `.done` and the harness records the run as `.red("hang")`.
- If the stream completes with **zero total tokens**, same behavior; harness records `.red("empty-output")`.
- Timer is re-armed after each token so slow-but-alive streams are not falsely killed.

### 6.4 Repetition guard (fixes B)

Lightweight n-gram loop detector: if the last 32 tokens contain a 6-gram that repeats ≥3 times, `StreamProcessor` stops reading from the raw stream, yields `.done`, and the UI renders a "truncated due to repetition" footer on the assistant bubble. Guard:

- **Off** inside `<think>` / `<thinking>` / `<reasoning>` blocks (thinking often repeats phrasing).
- **Off** inside fenced code blocks (between ``` markers) and inline code spans — code and poetry legitimately repeat (`for _ in 0..<n`, table rows, list items). The guard tracks whether the stream is currently inside a fence by counting unescaped ``` occurrences in the text buffer.
- **On** during normal assistant-channel prose.
- Threshold and n-gram length live under a **single master toggle** `AppSettings.streamProcessorV2Enabled` (default true). When disabled, all Section 6 behaviors (new tags, scrubber, hang watchdog, repetition guard) revert to the current `StreamProcessor` implementation. No per-sub-feature flags ship — the toggle is an emergency kill-switch only.

### 6.5 Tests (new, in `LocalAIEdgeAppTests`)

- `StreamProcessorTests` — new cases for each think format, boundary-split leak tokens, hang timeout (injected delayed stream), repetition trip at 3× 6-gram, empty stream fallback.
- `TokenLeakScrubberTests` — benign `<` characters in plain text must pass through; nested leak-in-word edge cases (e.g., `"<|im_end|>`" inside a code block) must still be stripped.
- All new tests run in simulator using mocked `AsyncStream<String>`.

## 7. Audit harness

### 7.1 `ModelAuditRunner` API

```swift
actor ModelAuditRunner {
    // Primary entry point — takes catalog items, handles install/uninstall lifecycle.
    func auditCatalog(
        items: [ModelCatalogItem],
        policy: InstallPolicy   // .requireInstalled / .installIfMissing(diskHeadroomGB: Double) / .installAndUninstall
    ) -> AsyncStream<ModelAuditProgress>

    // Secondary — for when a caller already has an installed model.
    func audit(model: InstalledModel, cases: [AuditCase], profile: RuntimeProfile?) async -> ModelAuditResult
}
```

The runner accepts **catalog items**, not `InstalledModel` only. The harness drives end-to-end: per item it checks disk headroom via `FileManager` free-space query, downloads via `ModelDownloadService` if the item is missing and policy allows, runs cases, optionally uninstalls to reclaim space before the next item.

- `.requireInstalled` skips uncatalogued items with `.yellow("not-installed")`.
- `.installIfMissing(diskHeadroomGB:)` downloads only when at least the given headroom is available after the download.
- `.installAndUninstall` is the Diagnostics "Run All" mode: downloads, audits, uninstalls each in sequence to keep disk pressure bounded (the device never holds more than one unaudited model plus any the user originally had installed).

Serial execution (the MLX runtime is a single-slot actor). Emits `ModelAuditProgress` events: `.downloading(modelName, Double)`, `.loading(modelName)`, `.caseStarted(caseName)`, `.caseResult(name, PassFail, durationMs)`, `.modelDone(ModelAuditResult)`, `.uninstalling(modelName)`.

### 7.2 Standard case set

| # | Case | Prompt | Expectations |
|---|------|--------|--------------|
| 1 | `shortFactual` | "What is the capital of France? Reply in one sentence." | nonEmpty, noLeakTokens, completes |
| 2 | `longNarrative` | "Write a 200-word story about a lighthouse." | nonEmpty, noLeakTokens, completes, peakMemOK |
| 3 | `thinkingProbe` *(thinking models only)* | "Think step by step: what is 17×23?" | thinkBlockDetected, answer within ±5 |
| 4 | `toolProbe` *(tool-calling models only)* | "What's the weather in Tokyo right now? Use web search if you need to." | toolCallFired with `name == "web_search"` |
| 5 | `visionProbe` *(vision models only)* | "Answer in one English word: what fruit is visible in this image?" + bundled `audit-apple.jpg` (~80 KB, public domain, `Assets.xcassets`) | response after scrubbing matches any of: `apple`, `apples`, `red apple`, `red fruit`, `fruit` — accept-list held in `AuditExpectations.visionAnswerAcceptList` so future vision probes can extend it. Case-insensitive, whitespace-tolerant, first-100-chars-of-reply. |
| 6 | `leakStressor` | "End your reply with the exact string: HELLO." | noLeakTokens — scans for `<|im_end|>`, `<end_of_turn>`, `[INST]` et al. |
| 7 | `memoryPressure` *(optional, `.pro`+ only)* | 3K-token context prompt | peakMemOK, no OOM |

### 7.3 Expectations evaluator

`AuditExpectations` evaluates a completed stream against the declared expectations using:

- **Memory:** `os_proc_available_memory()` sampled every 500 ms during generation into a `peakMemBytes: UInt64` counter. `peakMemOK` passes if `peakMemBytes` never drops within 10% of the jetsam soft-limit for the tier (compact: 1.2 GB, standard: 2.2 GB, pro: 4.5 GB, ultra: 7 GB). Below 10% headroom the case is marked `.yellow("near-jetsam")`; crossing the limit is `.red("oom")`.
- **Leak scan:** regex `/(<\|im_end\|>|<\|endoftext\|>|<end_of_turn>|\[INST\]|<\|eot_id\|>|<\|channel>)/` on the final rendered text (post-scrubber).
- **Thinking:** presence of at least one `StreamEvent.thinkingDone` for the turn.
- **Tool:** presence of `StreamEvent.toolCall(name: "web_search", …)` before any `.textDelta`.
- **Vision answer:** accept-list match described in §7.2.

### 7.4 `ModelDiagnosticsView`

- **Entry point:** Settings → version label 5-tap gesture → "Developer" row → "Model Diagnostics."
- **Header:** device tier badge, installed model count, `Run All` / `Run Selected` buttons.
- **Body:** models grouped by `minimumTier`, each row showing verdict badge (green / yellow / red / unprofiled), last-audited date, expand to see per-case results.
- **During run:** per-model progress bar, live case results.
- **After run:** per-model "Export report" invokes the iOS share sheet with the JSON payload. "Promote to RuntimeProfile" writes into `Documents/RuntimeProfiles.override.json` (Debug) or prompts for a share (Release, for manual commit).

### 7.5 Safety

- Runner checks free disk and memory before each case; aborts with a readable error if the device is low.
- Every loaded model is `unload()`'d between audits; `GPU.clearCache()` called explicitly.
- All raw streams + final reports written to `Documents/audits/<yyyy-MM-dd-HHmmss>/<modelID>.json`.

### 7.6 Release gating

- Release builds: screen exists but is hidden behind the 5-tap gate. No user-visible UX change.
- Debug builds: banner on any screen if any installed model's verdict is `.red`, nudging re-audit.

## 8. Build order

One branch (`codex/stabilize-local-edge-app`), seven incremental commits. Each commit must pass `xcodebuild test` before the next lands.

| # | Commit | Scope | Risk |
|---|--------|-------|------|
| 1 | `feat: DeviceTier classification` | Add `DeviceTier` enum; add `minimumTier` to `ModelCatalogItem`; annotate catalog; deprecate `recommendedForIPhone` (still decodable). | Low — additive. |
| 2 | `feat: RuntimeProfile JSON + loader` | Ship `RuntimeProfiles.json` at `.yellow` starter state; add loader + resolver; wire `ChatView` to consume profile-over-catalog. | Medium — changes runtime gating. |
| 3 | `fix: StreamProcessor tag + leak + hang + loop` | All of Section 6 in one commit. Behind `AppSettings.streamProcessorV2` (default true). | Medium — hot path. |
| 4 | `feat: ModelAuditRunner service` | Pure service, no UI. Exercised by `ModelAuditRunnerTests` with mock streams. | Low. |
| 5 | `feat: Model Diagnostics screen` | Hidden Developer menu + diagnostics UI. | Low. |
| 6 | `chore: catalog filter + download guard` | `ModelLibraryView` hides > tier by default; show-all toggle; download gate for oversize models. | Low. |
| 7 | `chore: run audit on device, promote profiles, commit JSON` | Run on the user's iPhone. Fix any red verdicts via code changes in earlier commits (amended or follow-up commits). Commit the green `RuntimeProfiles.json`. | None — data. |

## 9. Testing strategy

### 9.1 Unit (simulator-runnable via `xcodebuild test`)

- `DeviceTierTests` — every known `hw.machine` → correct tier.
- `RuntimeProfileTests` — JSON round-trip, missing file fallback, profile-over-catalog merge rules.
- `StreamProcessorTests` — all new behaviors plus existing coverage preserved.
- `TokenLeakScrubberTests` — boundary splits, benign `<`, nested leaks.
- `ModelAuditRunnerTests` — mocked `InferenceService` emitting scripted streams asserts pass/fail matrix matches expectations.

### 9.2 On-device (Commit 7)

Run the diagnostics harness on the user's physical iPhone. Fix any red cells via code changes, re-run until matrix is green for every model where `minimumTier ≤ deviceTier`.

## 10. Catalog pruning policy

After Commit 7: any MLX model whose final verdict is `.red` with a structural cause (empty output, unsupported architecture, persistent OOM on its claimed minimum tier) is **removed** from the catalog with a commit note citing the audit report. Yellow models stay shipped with a warning badge. No silent failures.

## 11. Deploy-to-device

Mechanical; already partly documented in `plan-localAIIphoneApp.prompt.md` and `DEPLOYMENT.md`.

1. `xcodegen generate` to regenerate the Xcode project from `project.yml`.
2. `xcodebuild -project LocalAIEdgeApp.xcodeproj -scheme LocalAIEdgeApp -destination 'id=<UDID>' -allowProvisioningUpdates build` with the user's iPhone plugged in. Apple ID signing via auto-provisioning. `com.apple.developer.applesignin` entitlement stays commented (free-account builds).
3. Install via `xcrun devicectl device install app --device <UDID> <path-to-.app>` and launch.
4. User runs the Model Diagnostics harness once on-device. Final green `RuntimeProfiles.json` is committed as the Phase 1 deliverable.

**Prerequisites from the user at deploy time:**

- iPhone UDID (`xcrun devicectl list devices` or Finder → device → tap version).
- Apple Developer Team ID (Xcode → Settings → Accounts).
- Developer Mode enabled on device (Settings → Privacy & Security → Developer Mode).
- "Trust this computer" confirmed.

## 12. Exit criteria for Phase 1

- [ ] All 7 commits merged on `codex/stabilize-local-edge-app`.
- [ ] `xcodebuild test` green locally and in commit history.
- [ ] Diagnostics harness run on the user's physical iPhone; matrix green for every model where `minimumTier ≤ deviceTier`.
- [ ] `RuntimeProfiles.json` committed with verified, dated verdicts.
- [ ] App installed on the user's phone; chat works; no token leaks; think-block renders collapsible; no OOM on installed models.

Only when those five boxes are ticked does Phase 2 (UI redesign) begin.

## 13. Open questions / explicit non-decisions

- **Phase 2 UI redesign** is deliberately out of scope here. The audit harness produced in Phase 1 is expected to carry into Phase 2 as a regression safety net.
- **Gemma-channel detector lives in shared `StreamProcessor`** even though the current GGUF Gemma entries are out of scope. This is an intentional decision: `StreamProcessor` is shared by both runtimes, and adding a detector that activates only when `RuntimeProfile.verifiedThinking == .gemmaChannel` is a pure-code addition with no behavioral effect on any currently shipped model (no MLX entry maps to `.gemmaChannel`, no GGUF entry has a `RuntimeProfile` yet). It is **not** a GGUF-path change — the detector is dead code until a future `RuntimeProfile` opts into it.
- **Search gateway and voice** are untouched.
- **Qwen 3 8B** stays in the catalog under `.ultra` instead of being removed, on the expectation that iPhone 17 Pro Max (12 GB) and iPad users exist.
- **iPhone 17 RAM assumption:** §4.1 lists iPhone 17 / 17 Pro as 8 GB based on the Apple Silicon A19 family memory configuration announced with the device. iPhone 17 Pro Max is classified as 12 GB (`.ultra`). These tiers are updated via a data-only commit if real-world `hw.machine` strings diverge from assumption.
- **`InstalledModel` vs catalog orchestration:** resolved in §7.1 — the runner accepts `ModelCatalogItem` and handles install/uninstall lifecycle with an `InstallPolicy`, so the harness works correctly against a mostly-empty device.
- **Per-model `contextWindow` vs runtime allocation:** the runner records `peakMemBytes` under the device's `tier.safeContextTokens`, not the catalog's declared `contextWindow` (40K/256K strings are aspirational; the runtime never allocates them on iPhone). A future follow-up could add a "long-context stress" case on `.ultra`-tier only.
