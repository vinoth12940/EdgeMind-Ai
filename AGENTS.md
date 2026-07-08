# AGENTS.md

This file provides guidance to AI coding agents (ZCode, Codex, Claude Code, etc.) when working with code in this repository.

**Edge Mind Ai** is an on-device iOS chat app that runs local LLM/VLM models across four runtimes — llama.cpp (GGUF), MLX, LiteRT-LM, and Apple Foundation Models — with optional agentic web search. The app does not ship or require a backend; all inference is local except the user-configured search gateway.

## Build & Test Commands

### Regenerate Xcode project (required after editing `project.yml`)
```bash
xcodegen generate
```

### Build for a connected device
```bash
xcodebuild -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'id=YOUR_DEVICE_UDID' \
  -allowProvisioningUpdates \
  build
```

### Build for simulator (GGUF only — MLX/LiteRT do not work in simulator)
```bash
xcodebuild -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Run unit tests (simulator)
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Run a single test class
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing EdgeMindAiTests/DeviceCapabilityTests
```

Note: the simulator excludes `x86_64` (`EXCLUDED_ARCHS[sdk=iphonesimulator*]: x86_64` in `project.yml`) — Apple Silicon hosts only.

No linter is configured — the project uses the Xcode compiler for type checking.

## Release & App Store submission

- **Current App Store state (July 8, 2026):** version `0.2.0`, build `5` has been uploaded, selected on the 0.2.0 App Store distribution page, and submitted for review. Version `0.1.0` remains the approved/live release until Apple approves 0.2.0. Both numbers live in `project.yml`; bump them there, then run `xcodegen generate` before archiving. `MARKETING_VERSION` is user-facing (`CFBundleShortVersionString`), `CURRENT_PROJECT_VERSION` is the build number (`CFBundleVersion`) and must increment on every new upload.
- **Bundle ID:** `com.vinothrajalingam.EdgeMindAi` (team `43NV5DTHKG`, paid Apple Developer Program). TestFlight is available; Sign-in-with-Apple can be re-enabled (it's currently off only because v0.1.0 doesn't need cloud auth — see Gotchas).
- **Submission docs to read before touching store-facing or privacy-sensitive areas:**
  - `APP_STORE_LISTING.md` — paste-ready App Store Connect metadata (title, subtitle, description, categories, privacy policy URL).
  - `APP_STORE_REVIEW_NOTES.md` — reviewer guidance (no remote auth, Apple Intelligence as the no-download test model, physical-device requirement for MLX, China mainland removed from availability for this version).
  - `docs/privacy.html` — the hosted privacy policy referenced by the listing.
- **Export compliance:** The app does not implement proprietary, custom, or non-standard encryption. It uses Apple/system-provided security such as HTTPS/TLS via iOS frameworks and Keychain storage. In App Store Connect's "App Encryption Documentation" flow, choose **"None of the algorithms mentioned above"** for "What type of encryption algorithms does your app implement?" The project also sets `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` in `project.yml`; do not remove it unless the app starts implementing non-exempt encryption.
- **Build selection in App Store Connect:** Uploading a new build does not automatically replace the build selected on the App Store version page. After upload processing completes, go to the 0.2.0 distribution page, remove the older selected build if needed, click **Add Build**, choose the newest build, click **Done**, then **Save**. On July 8, 2026, build `4` was still selected even after build `5` uploaded; build `5` had to be manually selected and saved before review submission.
- **LiteRT symbols:** `CLiteRTLM.framework` is vendored through `Vendor/LiteRT-LM` and needs its dSYM packaged for App Store uploads. `project.yml` contains the `Generate CLiteRTLM dSYM` post-build script. If Apple reports `CLiteRTLM.framework missing dSYM UUID`, verify the archive contains `dSYMs/CLiteRTLM.framework.dSYM` and that its UUID matches the embedded framework before uploading again.
- **Upload verification:** Treat Xcode's `UPLOAD SUCCEEDED with no errors` as upload completion, but still check App Store Connect/TestFlight for processing state. A build should show **Complete** and **Ready to Submit** before it is selected on a distribution page. For 0.2.0, build `5` was the correct submitted build; build `3` had missing compliance and build `4` was superseded.
- **Review constraints that constrain code changes:**
  - **No telemetry/analytics/cloud sync.** Any new networking must be opt-in and user-facing (the only outbound calls are the user-configured `SearchGateway` and HuggingFace model downloads).
  - **China mainland is removed from availability** for current submissions — do not add China-specific storefront logic without coordinating.
  - **Guideline 2.5.2 (static weights):** GGUF/MLX/LiteRT model files are data, not executables. Do not introduce code that downloads or runs remote executable code.
  - **MLX/LiteRT need a physical device** (simulator can't run them) — review notes tell reviewers to test MLX on real hardware. Keep the simulator guards (`#if ... && !targetEnvironment(simulator)`) intact.
  - **No remote account/auth** is required to use the app; the guest profile must always reach core chat without login.

## Project Structure

The app target is **`EdgeMindAi`** (renamed from the earlier `LocalAIEdgeApp`); the test target is **`EdgeMindAiTests`**. Older source files may still carry a `// LocalAIEdgeApp/...` header comment — that is historical, not a current path. The Xcode project is generated from `project.yml` using XcodeGen. **Never edit `.xcodeproj` directly.** The source of truth is `project.yml` + Swift source files.

```
EdgeMindAi/             # Main app target
  App/                  # EdgeMindAiApp (@main), RootView (tab nav), LocalAIAppIntents
  Models/               # Codable data structs (AppSettings, ChatMessage, ChatSession,
                        #   InstalledModel, ModelCatalogItem, SearchContext)
  State/                # AppStateStore, AuthStateStore, MockCatalogData
  Services/
    Inference/          # InferenceService protocol + 4 runtime backends, StreamProcessor,
                        #   ModelRuntimeResolver, RuntimeProfile(Store), ModelAuditRunner,
                        #   DeviceCapabilityService, DeviceTier, RuntimeMemoryCoordinator,
                        #   ResponsibleAIGuard, TokenLeakScrubber
    Tools/              # Tool protocol + ToolRegistry + concrete tools (v0.2.0),
                        #   PromptTemplateStore
    Models/             # ModelDownloadService, ModelCatalogService
    Search/             # SearchGateway protocol + Tavily/Brave/Serper/Custom + refiner
    Voice/              # VoiceInteractionController (iOS STT/TTS)
    Attachments/        # DocumentExtractionService (TXT/MD/CSV/PDF/image text)
    HFTokenManager.swift
  Features/             # SwiftUI views by domain (Auth, Chat, Models, History, Settings)
  DesignSystem/         # AppTheme — colors, gradients, view modifiers
  Resources/            # Assets, PrivacyInfo.xcprivacy, RuntimeProfiles.json
EdgeMindAiTests/        # Unit test target (XCTest)
docs/                   # product.md, runtime-evaluation.md, privacy.html
Vendor/build-apple/     # Pre-built llama.cpp xcframework (vendored in-repo)
Vendor/LiteRT-LM/       # Local Swift package for the LiteRT runtime
```

## Architecture

### State layer (`State/`)
`AppStateStore` is an `@Observable` class injected at the SwiftUI root and holds all runtime state: catalog, installed models, chat sessions, settings. All mutations go through its `func` methods (not direct property writes). `AuthStateStore` is a separate `@Observable` for auth state (Apple ID / local / guest / device biometrics).

Persistence uses `UserDefaults` via JSON encoding. Images in chat history are sanitized before persistence (`sanitizedSessionForPersistence`) to avoid oversized writes (threshold: 600 KB per image).

`AppStateStore.reconcileInstalledFiles()` is called at launch to reconcile GGUF files present on disk with persisted `InstalledModel` records — it scans the models directory and calls `markInstallCompleted` for any matching files.

### Inference layer (`Services/Inference/`)
Four concrete backends behind the `InferenceService` protocol, selected by `ModelCatalogItem.RuntimeType` (`.gguf`, `.mlx`, `.liteRTLM`, `.foundationModels`):

- **`LocalLlamaInferenceService`** — GGUF models via llama.cpp C API. Contains the `PromptRenderer` enum (token budget calculation, HTML stripping, chat-turn assembly). `PromptRenderer` is `internal` for testability. Does **not** support image input — throws if `imageData != nil`.
- **`MLXInferenceService`** — MLX models via the `mlx-swift-lm` package (MLXLLM, MLXVLM). Falls back to a plain prompt string for models without a chat template. Only loads the SigLIP vision tower when `imageData != nil && supportsVision` to prevent OOM on 8 GB devices.
- **`LiteRTInferenceService`** — Gemma 4 E2B/E4B via the local `Vendor/LiteRT-LM` Swift package. Supports vision for the E2B variant; image streams are bounded by timeouts and cancellation (`ef11cd5`, `92e8977`).
- **`AppleFoundationModelService`** — Apple Intelligence Foundation Models (on-device system runtime, no downloaded weights). Gated by `AppleFoundationModelService.availabilityMessage`; throws when unavailable. The catalog's "Apple Intelligence" entry (`runtimeType: .foundationModels`) is the only path that uses it.

`ChatView` holds one `@State` instance per backend and routes via `inferenceServiceForModel(_:)`, which `switch`es on `runtimeType`. Before each call it calls `RuntimeMemoryCoordinator.prepareForRuntime(...)` to free the previous runtime's memory.

`AssistantResponseSanitizer.clean()` (in `InferenceService.swift`) strips model-specific tokens (`<|im_end|>`, `[INST]`, etc.) from streamed output before display. `TokenLeakScrubber` additionally scrubs per-model `knownLeakTokens` declared in the runtime profile. `ResponsibleAIGuard` is a pre-flight safety filter on outgoing prompts.

**Context and token budgets** — `InferenceBudget` is the single source of truth:
- `safeContextWindow(for:)` clamps per runtime: GGUF uses `DeviceCapabilityService.contextSize()`, MLX/FoundationModels use `DeviceTier.safeContextTokens`, LiteRT caps at 2048.
- `maxGeneratedTokens(for:searchContext:)` = 1024 chat / 2048 with search, capped to `contextWindow - 256`.
- `mlxHistoryBudget(...)` reserves prompt space and returns the history token budget.
Do not hardcode prompt/context limits — always go through `InferenceBudget`.

**`DeviceCapabilityService`** reads `hw.machine` via `sysctlbyname` for GGUF `n_ctx` selection and flash-attention gating (A14 = disabled). The cross-runtime tier system is `DeviceTier` (see below).

### Stream processing (`Services/Inference/StreamProcessor.swift`)
`StreamProcessor` is an `actor` that sits between the raw `AsyncStream<String>` from inference backends and the UI. It parses the token stream into typed `StreamEvent` values: `.textDelta`, `.thinkingDelta`, `.thinkingDone`, `.toolCall`, and `.done`. Both `LocalLlamaInferenceService` and `MLXInferenceService` wrap their raw streams through `StreamProcessor` before returning.

Key behaviors:
- **Think block extraction**: Detects `<think>`, `<thinking>`, `<reasoning>` tags (case-insensitive) and routes content to `.thinkingDelta`/`.thinkingDone` events. Auto-closes unclosed think blocks at stream end.
- **Tool call parsing**: Detects `<tool_call>…</tool_call>` blocks, parses the JSON for a `name` field, and yields `.toolCall`. Only one tool call per stream is honored (`toolCallFired` guard) — subsequent `<tool_call>` blocks are flushed as plain text.
- **Tag splitting caveat**: Tags split across token boundaries (e.g. `"<thi"` + `"nk>"`) are not detected. This is a known trade-off documented in the code.

`MockInferenceService` (in `Services/Inference/`) provides a stub for SwiftUI previews and unit tests.

### Device tiers (`DeviceTier.swift`)
`DeviceTier` (`compact` / `standard` / `pro` / `ultra`, by RAM: 4 / 6 / 8 / 12 GB+) is the cross-runtime capacity oracle. Each tier exposes `safeContextTokens` (2048 / 4096 / 8192 / 16384), `recommendedModelSizeGB`, and a `label`. `ModelCatalogItem.minimumTier` (default `.standard`) gates whether a model is allowed to install/run on the current device. Prefer `DeviceTier.current()` and `tier.safeContextTokens` over the older GGUF-only `DeviceCapabilityService.contextSize()` for MLX/LiteRT/FoundationModels paths.

### Runtime profiles & model audit (`RuntimeProfile*.swift`, `ModelAudit*.swift`)
Per-model runtime reality lives in **`EdgeMindAi/Resources/RuntimeProfiles.json`** (bundled, read once by `RuntimeProfileStore`), NOT in the catalog. A `RuntimeProfile` records what is actually verified in this app: `verifiedThinking: ThinkFormat?`, `verifiedToolCalling: ToolCallFormat?`, `verifiedVision: VisionMode`, `verifiedInputModes`, `knownLeakTokens`, `recommendedMaxTokens`, `auditVerdict: Verdict`.

- **`ModelRuntimeResolver.resolve(catalog:store:)`** merges a catalog entry with its profile into a `ResolvedModel`, and flags `isMismatch` when the catalog *claims* a capability (e.g. `supportsVision`) the profile has **not** verified. The UI surfaces "claimed but not verified" from this flag.
- **Catalog = advertised capability; Profile = verified capability.** When they disagree, trust the profile for runtime behavior; update the catalog flag only if the upstream claim itself is wrong.
- `RuntimeProfileStore` has an opt-in `OverridePolicy` that reads a Documents override file. Normal launches use `disabled` — do not silently mutate behavior via a stale override.
- `ModelAuditRunner` / `HeadlessModelAuditLauncher` run probes against installed MLX/LiteRT models and write results back to `RuntimeProfiles.json` (MLX) or update verdicts. Foundation Models and GGUF entries are skipped by the launcher. `RuntimeMemoryCoordinator.prepareForRuntime/releaseAfterAudit` brackets each audit run to avoid OOM.
- **The `raiSafety` audit case grades the model's OWN refusal via `ResponsibleAIGuard.isSafeRefusal`** (production blocks the unsafe prompt before inference; the audit deliberately bypasses that to test the model). `isSafeRefusal` was a brittle fixed-phrase list that scored common real refusals ("I can't provide instructions on how to…") as `rai-refusal-missing`, cascading good models to a **false `red` verdict** — this was the main reason lightweight MLX models were stuck yellow/red. It now uses a leading-window refusal-verb + assistance-verb pattern (note: `normalize` turns `can't` into `can t`). A failed `raiSafety` case skips the rest and reds the model, so a false negative here is high-impact — keep `ResponsibleAIGuardTests` green when touching it.
- **On-device audit harness is flaky for heavy/reasoning models**: Phi 3.5 Mini (3.8B) reproducibly gets jetsam-killed mid-`longNarrative` generation (real memory limit → honest yellow, not a checker bug); reasoning models (DeepSeek R1) and HF downloads can hang the `devicectl --console` launch. Use `--localai-audit-case-timeout-sec` to bound each case; macOS has no GNU `timeout` for an outer wrapper. Run heavy models one at a time and watch for download stalls at 0%. Scripts live in `scratch/run-device-audit*.sh`.

### Model catalog (`State/MockCatalogData.swift`)
Static array of `ModelCatalogItem` structs — currently ~49 entries spanning Apple Intelligence, Granite, Gemma (2/3/4), Llama, Phi, DeepSeek, Mistral, SmolLM, Qwen (3 / 3.5 VL), and LFM 2.5 families across GGUF, MLX, LiteRT-LM, and FoundationModels runtimes. Each entry carries both *advertised* and *runtime* fields:

- **Advertised capability**: `supportsVision`, `supportsToolCalling`, `isThinkingModel`, `supportsReasoning`, `sourceSupportsVision`, `recommendedForIPhone`.
- **Runtime/audit fields**: `runtimeStatus: ModelRuntimeStatus` (`.recommended`/`.worksWithWarnings`/`.experimental`), `auditVerdict: Verdict` (`.green` / `.yellow(reason)` / `.red(reason)`), `testedDeviceTier: DeviceTier?`, `inputModes: [InputCategory]` (what this app actually accepts: text/image/document).
- The *verified* behavior also lives in `RuntimeProfiles.json` (see Runtime profiles section). `ModelRuntimeResolver` reconciles catalog claims with the profile and flags `isMismatch`.

`ModelCatalogItem` derives `sourceInputCategories` (upstream support) and `runtimeInputCategories` (what this app accepts) for UI disclosure. Example: GGUF vision-family entries may show source `Text + Image` but runtime `Text` because the current llama.cpp path is text-only.

`supportsReasoning` and `isThinkingModel` are distinct flags: `isThinkingModel` means the model uses a native `<think>…</think>` streaming block (e.g. Qwen 3); `supportsReasoning` is a softer capability label. `sourceSupportsVision` describes the upstream model; `supportsVision` describes whether *this app* enables image input for it (e.g. Gemma 4 E4B has `sourceSupportsVision: true` but `supportsVision: false` after its on-device vision audit failed).

Voice models should only be cataloged when there is a fully wired inference/runtime path for them. `VoiceInteractionController` itself uses iOS STT/TTS and is independent from chat model inference.

### Runtime model storage
- **GGUF** (`.gguf`) — downloaded to the app's Documents directory via `URLModelDownloadService`. `InstalledModel.localPath` (and `fileURL`) points to the file on disk. Loaded by `LocalLlamaInferenceService`.
- **MLX** — downloaded to the system caches directory by the HuggingFace Hub library. `InstalledModel.localPath` is not used; the runtime loads from `ModelCatalogItem.mlxModelID` (a HF repo ID string like `"mlx-community/gemma-2-2b-it-4bit"`). Loaded by `MLXInferenceService`.
- **LiteRT-LM** (`.litertlm`) — Gemma 4 E2B/E4B task bundles downloaded from `huggingface.co/litert-community/...`. Loaded by `LiteRTInferenceService` from `Vendor/LiteRT-LM`.
- **FoundationModels** — Apple Intelligence system runtime; no download, no on-disk weights. `AppleFoundationModelService` throws with an availability message on unsupported devices.

### Deterministic IDs are namespaced
`DeterministicID` (`Models/DeterministicID.swift`) generates UUID v5 (SHA-1) IDs shared across bundled entities. Each entity type has its **own namespace** so IDs never collide: `modelCatalogNamespace`, `toolNamespace`, `promptTemplateNamespace`. `ModelCatalogItem.id` = `"\(displayName)::\(variant)"`; `PromptTemplate.id` = `"\(slug)::\(category)"`. **Do not rename the inputs of an existing entry** — doing so generates a new UUID, orphaning persisted records (`InstalledModel` for catalog, future user templates for prompts).

### Voice layer (`Services/Voice/`)
`VoiceInteractionController` is a `@MainActor ObservableObject` wrapping `SFSpeechRecognizer` (STT) and `AVSpeechSynthesizer` (TTS). It exposes `transcript`, `isListening`, and `isSpeaking` as `@Published` state. Requires microphone + speech recognition permissions at runtime. This path is currently independent from GGUF/MLX chat inference models.

### Search layer (`Services/Search/`)
`SearchGateway` protocol with four implementations: Tavily, Brave, Serper, and `CustomSearchGateway` (a passthrough POST to a user-provided URL; `SearchGatewayFactory` normalizes its path to `/api/search`). `SearchGatewayFactory.make(settings:)` picks the active provider from `AppSettings.webSearchProvider`; the `none`/custom case builds a `CustomSearchGateway` only if a gateway URL is configured. API keys live in the **Keychain** (`WebSearchKeyManager` in `Services/KeychainSecretStore.swift`); `AppSettings.webSearchAPIKey` is an in-memory working copy that is excluded from the persisted settings JSON and restored from the Keychain by `AppStateStore` at launch (legacy plaintext values are migrated and scrubbed). `SearchQueryRefiner` rewrites the user query before it is sent. The iOS app does not ship or require a backend service.

### Agentic tool-calling (v0.2.0)
Tool-calling models (catalog `supportsToolCalling` **and** a `verifiedToolCalling` profile) drive a multi-step agentic loop. The model receives the user message with a `# Tools` prompt section (rendered by `ToolRegistry.renderPromptSection`) and may emit a `<tool_call>` block. `StreamProcessor` yields `.toolCall(name, argsJSON)`; `ChatView.runToolLoop` then dispatches via `ToolRegistry`, appends the tool's result text to the system prompt, and re-invokes inference — looping up to `ToolRegistry.maxIterations` (3) times so the model can chain tool calls. Non-tool-calling models fall back to upfront search (auto-detect or user toggle). `web_search` keeps its structured `searchContext` render path unchanged; all other tools render as plain `# Tool result:` text appended to the system prompt. **No `InferenceService` signature change** — tool results never touch the protocol.

### Tools layer (`Services/Tools/`)
`Tool` protocol + `ToolRegistry` (the central registry). `ToolRegistry.availableTools(context:)` gates which tools a turn exposes (e.g. `web_search` only with a configured provider, `read_document` only with an attached doc, `search_chats` only with history). `dispatch(name:argsJSON:context:)` routes a model's `<tool_call>` to the right tool, case-insensitively, returning nil for unknown names. Concrete tools:
- **`WebSearchTool`** — wraps `SearchGatewayFactory` + `SearchQueryRefiner`; returns `ToolResult` with `searchContext` + `citations` for the existing render path.
- **`CalculateTool`** — safe recursive-descent arithmetic evaluator (`+ - * / % ^`, parens, `sqrt/sin/cos/tan/log/ln/abs/round/floor/ceil/min/max`). **No `NSExpression`, no eval** — pure deterministic parser. `MathEvaluator.stripNumericCommas` strips thousands separators (`1,000`) but preserves argument-separator commas (`max(3, 9)`).
- **`GetCurrentTimeTool` / `GetDeviceInfoTool` / `GetBatteryLevelTool`** — read-only device facts (no PII).
- **`SearchHistoryTool`** — searches the user's own past `ChatSession`s locally; 100% on-device.
- **`ReadDocumentTool`** — returns extracted text from an attached document via `DocumentExtractionService`.

`ToolContext` bundles per-turn dependencies (settings, conversation, chatSessions, attachedDocuments, installedModel). All tool execution is on-device; `web_search` is the only tool that makes a network call, and only through the user-configured gateway.

### Prompt Library (v0.2.0)
~14 built-in prompt templates (Writing / Code / Learning / Productivity) surfaced from the composer's `+`/paperclip menu. `PromptTemplate` (Codable, UUID v5 from `slug::category`) is loaded from `EdgeMindAi/Resources/PromptTemplates.json` by `PromptTemplateStore` (mirrors `RuntimeProfileStore`'s bundled-loader pattern). `PromptLibraryView` is a `.sheet` that inserts the chosen template body into the composer's `prompt` binding. v0.2.0 ships built-in templates only — user-created templates are a future feature.

### HuggingFace token storage
`HFTokenManager` stores the HF token in the iOS **Keychain** (not UserDefaults); like the search key, `AppSettings.huggingFaceToken` is a non-persisted in-memory mirror. Both managers share `KeychainSecretStore` primitives. Used by `ModelDownloadService` to add `Authorization: Bearer` headers for gated model downloads, and by `MLXRuntime` when building the `HubApi` for MLX model loading.

### Key wiring points
- `EdgeMindAiApp.swift` (@main): injects `AppStateStore` and `AuthStateStore` into the environment, gates `RootView` behind auth via `LaunchRootView`, and applies `.preferredColorScheme(store.settings.appearanceMode.preferredColorScheme)` at the window level.
- `ChatView.swift`: holds one `@State` `InferenceService` per runtime, selects via `inferenceServiceForModel(_:)` (switch on `runtimeType`), calls `RuntimeMemoryCoordinator.prepareForRuntime(...)` before each call, and drives the streaming loop by consuming `StreamEvent` values from `StreamProcessor`. Handles `.textDelta` (batched UI updates), `.thinkingDelta`/`.thinkingDone` (routed to `store.updateMessageThinking`), and `.toolCall` (triggers agentic search re-invocation).
- `ModelLibraryView.swift`: triggers downloads via `ModelDownloadService`, updates progress through `AppStateStore.updateInstallProgress()`.
- Cross-tab navigation uses `SelectedTabKey` `EnvironmentKey` — inject `@Environment(\.selectedTab)` and write to switch tabs without tight coupling.

## Adding a New Model to the Catalog

1. Add a `static let url` constant in the URL section of `MockCatalogData.swift` (GGUF/MLX only — LiteRT-LM and FoundationModels entries do not need a download URL).
2. Add a `ModelCatalogItem(...)` entry in `items`. Set `runtimeType` correctly:
   - `.gguf` + `downloadURL` → file downloaded to Documents, loaded by `LocalLlamaInferenceService`.
   - `.mlx` + `mlxModelID` (HF repo ID) → loaded by `MLXInferenceService` from the HF caches dir.
   - `.liteRTLM` → Gemma 4 E2B/E4B via `Vendor/LiteRT-LM`; no `downloadURL`/`mlxModelID`.
   - `.foundationModels` → Apple Intelligence system runtime; no weights, no ID.
3. Use `supportsVision: true` only if the model has a vision encoder in its weights. Use `supportsToolCalling: true` only if the model has native `<tool_call>` or equivalent tokens in its chat template (not just prompt-level function calling).
4. Qwen 3 models get `isThinkingModel: true` (native `/think`/`/no_think` switches) — **except the 2507-refresh `Instruct` variants** (e.g. Qwen 3 4B 2507 Instruct), where Qwen split thinking into a separate `Thinking` model; the 2507 Instruct variants are non-thinking.
5. Set `minimumTier` honestly — models over ~4 GB should be `.pro`/`.ultra` and should not set `recommendedForIPhone: true` for compact devices.
6. **Add a matching `RuntimeProfile` entry to `EdgeMindAi/Resources/RuntimeProfiles.json`** with the same `catalogID` (UUID v5). Without it, `ModelRuntimeResolver` falls back to `RuntimeProfile.safeMinimum(...)` and the UI will show every claimed capability as an unverified mismatch. Set `verifiedThinking`/`verifiedToolCalling`/`verifiedVision` only after probing the model in this app.

## llama.cpp xcframework

The pre-built xcframework at `Vendor/build-apple/llama.xcframework` is vendored in-repo and linked directly via `project.yml` (`embed: true`, `codeSign: true`). Do not replace or update the xcframework without rebuilding all test targets. The LiteRT runtime is pulled from the local `Vendor/LiteRT-LM` Swift package (declared under `packages:` in `project.yml`); MLX comes from `mlx-swift-lm`, and HF/tokenizer support from `swift-huggingface` + `swift-transformers`.

## Gotchas

- **Gemma 4 runs on LiteRT-LM, not MLX**: The Gemma 4 E2B/E4B catalog entries use `runtimeType: .liteRTLM` and load via `LiteRTInferenceService` from `Vendor/LiteRT-LM`. The E2B variant supports vision; the **E4B vision path failed the on-device audit** (`image-runtime-failed-xnnpack-allocation`), so its catalog entry has `supportsVision: false` and a `.yellow(...)` `auditVerdict` — it is text+document only despite the upstream E4B being a VLM.
- **Gemma 4 thinking token format**: Gemma 4 models use `<|channel>thought\n...<channel|>` tokens for their thinking/reasoning block, NOT `<think>` tags. `StreamProcessor` CAN parse this (`ThinkFormat.gemmaChannel`), but only when the model's RuntimeProfile sets `verifiedThinking: "gemmaChannel"` (that's what populates `activeThinkFormats`). No profile sets it yet, so Gemma 4 thinking still renders inline and `isThinkingModel: false` remains correct in the catalog — flip profile first (after a device probe), then the catalog flag.
- **Gemma 4 native tool-call payload is NOT JSON**: Gemma 4 emits `<|tool_call>call:NAME{key:<|"|>value<|"|>, n:30}<tool_call|>` (typed arguments, per Google's Gemma 4 prompt-formatting docs). `GemmaToolCallPayload` (in `StreamProcessor.swift`) converts this to the app's `(name, argsJSON)` shape; `StreamProcessor.parseToolCall` tries it before the JSON path. `GemmaToolCallPayloadTests` locks one stream-level fixture per declared `ToolCallFormat` — keep that invariant when adding formats.
- **Qwen 3.5 models are VLMs**: All Qwen 3.5 sizes (0.8B–9B) have a vision encoder. They accept `image_url` inputs and report VideoMME benchmark scores. In the MLX app, image input works via `VLMModelFactory`. Context is 256K tokens (262,144), not 32K. The MLX repo IDs are `mlx-community/Qwen3.5-{size}-4bit` (no "VL" in the name) — model-ID string checks must match `qwen3.5-4b`, not `qwen3-vl-4b`.
- **Qwen 3.5 VL 4B image path**: its first on-device image audit was OOM-killed (`image-prefill-memory-killed-on-device-text-only`) because the old model-ID check never matched, so it ran the generic 384px/unbounded-KV path. It now gets the constrained-vision treatment (192px, `kvBits: 4`, `prefillStepSize: 16`, wired-memory ticket — see `isConstrainedVisionModel` in `MLXInferenceService`). Catalog stays `supportsVision: false` until an on-device re-audit passes; then flip catalog `supportsVision` + `inputModes` + profile `verifiedVision` together. Gemma 4 E4B (LiteRT) vision remains a vendor xnnpack limitation — retry only after the next `Vendor/LiteRT-LM` update.
- **Gemma 4 context**: Gemma 4 E2B and E4B support 128K tokens in context (all catalog entries now say 128K; `CatalogConsistencyTests` enforces that the same model advertises the same context window across runtimes). The LiteRT-LM runtime exposes the full context via the model weights, though `InferenceBudget` still clamps LiteRT to 2048 at runtime.
- **LFM2.5 VL tool calling is text-only**: Per the official docs, `LFM2.5-VL-1.6B` supports tool calling for text-only inputs. Tool calls will not fire when the message content includes an image.
- **LFM2.5-1.2B-Thinking is a separate model**: The `LFM2.5-1.2B-Instruct` model does NOT have a thinking mode. Thinking is available only in `LFM2.5-1.2B-Thinking` (a distinct model variant). The catalog carries the `Thinking` variant (with `isThinkingModel: true`); do not set `isThinkingModel: true` on the Instruct variant.
- **`PromptRenderer` dynamic budget**: `maxPromptTokens = max(256, nCtx - maxGeneratedTokens - 64)`. On a 2048 n_ctx device in search mode, this floors at 256 tokens. Do not hardcode prompt limits.
- **Context reuse**: `LocalLlamaRuntime.ensureContext()` reloads when `maxGeneratedTokens` changes (search vs. chat mode). Switching between modes triggers a full model reload.
- **MLX/LiteRT on simulator**: MLX calls are guarded by `#if canImport(MLXLLM) && !targetEnvironment(simulator)`; LiteRT-LM likewise does not run in the simulator. Only GGUF models work in the simulator. The simulator also excludes `x86_64`, so Apple Silicon hosts are required.
- **Sign in with Apple**: `com.apple.developer.applesignin` is currently commented out in `EdgeMindAi.entitlements`. The team is on a **paid** Apple Developer Program, so it can be re-enabled — it was left disabled because the v0.1.0 submission does not require cloud auth, and `APP_STORE_REVIEW_NOTES.md` tells reviewers the app needs no remote account. Re-enable it only if you intend to ship SiwA in a future version.
- **`project.yml` is the source of truth**: Running `xcodegen generate` overwrites `.xcodeproj`. Stage `project.yml` changes before generating.
- **Design system supports light + dark**: `AppTheme` defines `light` and `dark` variants for every color and adapts via `UITraitCollection.userInterfaceStyle`. `AppSettings.appearanceMode` (`.system` default / `.dark` / `.light`) is applied once at the window root via `.preferredColorScheme(...)`. Do not add per-view `colorScheme` conditionals — extend `AppTheme` if a new adaptive color is needed.
- **Citations are not a chat role**: `ChatMessage.Role` is `system`/`user`/`assistant` only — the legacy `.search` role has been removed. Search citations live on `ChatMessage.citations: [SearchCitation]` and should render as a "Sources" footer on the assistant bubble. Do not reintroduce a `.search` role.
- **App Intents handoff**: `LocalAIAppIntents.swift` defines `OpenLocalAIDestinationIntent`, `AskDefaultLocalModelIntent`, and `StartLocalVoiceChatIntent`. They stash a `LocalAIIntentDestination` (`.chat`/`.models`/`.voice`) + optional prompt/voice flag via `LocalAIIntentBus.save(...)`, which the UI consumes once on launch via `consume*()`. When wiring new shortcuts/Siri intents, route through the bus rather than touching `AppStateStore` directly from the intent.
- **Image attachments are downsampled before inference**: `ChatComposerView` bounds JPEG encoding to prevent OOM. Do not pass raw `UIImage` to the inference service.
- **MLX GPU cache**: `MLXRuntime` unloads the previous model and calls `GPU.clearCache()` before loading a new one. Vision models get a larger cache limit (768 MB vs 512 MB) to accommodate the SigLIP tower. `RuntimeMemoryCoordinator.prepareForRuntime(...)` is the cross-runtime entry point `ChatView` calls before every inference call — it unloads the previous runtime so GGUF/MLX/LiteRT/FoundationModels do not co-occupy memory.
- **Tool loop is bounded (`ToolRegistry.maxIterations = 3`)**: `ChatView.runToolLoop` re-invokes inference after each tool result; a model that keeps emitting `<tool_call>` is capped at 3 iterations, after which a "tool-call limit" system message is shown. The loop lives in `ChatView`, NOT in `StreamProcessor` — the parser still terminates the *current* stream on the first tool call (correct: the model is signaling it wants a tool).
- **`CalculateTool` thousands-separator commas vs argument commas**: `MathEvaluator.stripNumericCommas` strips a comma ONLY when it sits between two digits (`1,000` → `1000`), so function-argument commas (`max(3, 9)`) are preserved. Do not revert to a blanket `replacingOccurrences(of: ",", with: "")` — it breaks multi-argument functions.
- **`web_search` keeps its structured render path**: even though it's now a `Tool`, `WebSearchTool` returns `ToolResult.searchContext`, which `ChatView` passes through `generateStream(searchContext:)` so the existing `PromptRenderer`/`MLXInferenceService.buildSystemPrompt` snippet rendering is unchanged. Do not migrate `web_search` to the plain-text `# Tool result:` path without unifying the two renderers.
- **Composer body type-checker fragility**: `ChatComposerView.body` is large enough that adding modifiers can trip Swift's "unable to type-check in reasonable time" error. Sheets/alerts/pickers live in a `private View` extension (`composerPresentationModifiers`) and the trailing button group is extracted to `trailingAction`. Add new composer modifiers to the extension, not inline in `body`.
