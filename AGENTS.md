# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Test Commands

### Regenerate Xcode project (required after editing `project.yml`)
```bash
xcodegen generate
```

### Build for a connected device
```bash
xcodebuild -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'id=YOUR_DEVICE_UDID' \
  -allowProvisioningUpdates \
  build
```

### Build for simulator (GGUF only — MLX does not work in simulator)
```bash
xcodebuild -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Run unit tests (simulator)
```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Run a single test class
```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/DeviceCapabilityTests
```

No linter is configured — the project uses the Xcode compiler for type checking.

## Project Structure

The Xcode project is generated from `project.yml` using XcodeGen. **Never edit `.xcodeproj` directly.** The source of truth is `project.yml` + Swift source files.

```
LocalAIEdgeApp/          # Main app target
  App/                   # Entry point, RootView (tab nav)
  Models/                # Codable data structs
  State/                 # AppStateStore, AuthStateStore, MockCatalogData
  Services/
    Inference/           # InferenceService protocol + GGUF/MLX implementations
    Models/              # ModelDownloadService, ModelCatalogService
    Search/              # SearchGateway protocol + 4 implementations
    Voice/               # VoiceInteractionController (STT/TTS)
  Features/              # SwiftUI views by domain (Auth, Chat, Models, History, Settings)
  DesignSystem/          # AppTheme — dark-mode-only colors, gradients, view modifiers
LocalAIEdgeAppTests/     # Unit test target (XCTest)
  DeviceCapabilityTests.swift
  PromptRendererTests.swift
  StreamProcessorTests.swift
Vendor/build-apple/      # Pre-built llama.cpp xcframework (vendored in-repo)
```

## Architecture

### State layer (`State/`)
`AppStateStore` is an `@Observable` class injected at the SwiftUI root and holds all runtime state: catalog, installed models, chat sessions, settings. All mutations go through its `func` methods (not direct property writes). `AuthStateStore` is a separate `@Observable` for auth state (Apple ID / local / guest / device biometrics).

Persistence uses `UserDefaults` via JSON encoding. Images in chat history are sanitized before persistence (`sanitizedSessionForPersistence`) to avoid oversized writes (threshold: 600 KB per image).

`AppStateStore.reconcileInstalledFiles()` is called at launch to reconcile GGUF files present on disk with persisted `InstalledModel` records — it scans the models directory and calls `markInstallCompleted` for any matching files.

### Inference layer (`Services/Inference/`)
Two concrete inference backends behind the `InferenceService` protocol:

- **`LocalLlamaInferenceService`** — GGUF models via llama.cpp C API. Contains the `PromptRenderer` enum (token budget calculation, HTML stripping, chat-turn assembly). `PromptRenderer` is `internal` for testability. Does **not** support image input — throws if `imageData != nil`.
- **`MLXInferenceService`** — MLX models via `mlx-swift-examples` (MLXLLM, VLMModelFactory). Falls back to a plain prompt string for models without a chat template. Only loads the SigLIP vision tower when `imageData != nil && supportsVision` to prevent OOM on 8 GB devices. Current integration is LLM/VLM (text + image); it does not include a dedicated MLX audio inference path.

Both backends use **singleton actors** (`LocalLlamaRuntime.shared`, `MLXRuntime.shared`) for thread-safe C/MLX interop. The actors hold the loaded model context and reuse it across calls when model path and `maxGeneratedTokens` are unchanged.

`ChatView` holds two `@State` inference service instances and selects between them at call time via `inferenceServiceForModel(_:)` which checks `runtimeType == .mlx`.

**`DeviceCapabilityService`** reads `hw.machine` via `sysctlbyname` to select:
- `n_ctx`: 2048 (A14/iPhone 12), 4096 (A15/A16), 8192 (A17/A18/iPad/Simulator)
- Flash attention: disabled on A14, enabled on A15+

`maxGeneratedTokens` is 1024 for chat and 2048 when a `SearchContext` is present.

`AssistantResponseSanitizer.clean()` (in `InferenceService.swift`) strips model-specific tokens (`<|im_end|>`, `[INST]`, etc.) from streamed output before display.

### Stream processing (`Services/Inference/StreamProcessor.swift`)
`StreamProcessor` is an `actor` that sits between the raw `AsyncStream<String>` from inference backends and the UI. It parses the token stream into typed `StreamEvent` values: `.textDelta`, `.thinkingDelta`, `.thinkingDone`, `.toolCall`, and `.done`. Both `LocalLlamaInferenceService` and `MLXInferenceService` wrap their raw streams through `StreamProcessor` before returning.

Key behaviors:
- **Think block extraction**: Detects `<think>`, `<thinking>`, `<reasoning>` tags (case-insensitive) and routes content to `.thinkingDelta`/`.thinkingDone` events. Auto-closes unclosed think blocks at stream end.
- **Tool call parsing**: Detects `<tool_call>…</tool_call>` blocks, parses the JSON for a `name` field, and yields `.toolCall`. Only one tool call per stream is honored (`toolCallFired` guard) — subsequent `<tool_call>` blocks are flushed as plain text.
- **Tag splitting caveat**: Tags split across token boundaries (e.g. `"<thi"` + `"nk>"`) are not detected. This is a known trade-off documented in the code.

`MockInferenceService` (in `Services/Inference/`) provides a stub for SwiftUI previews and unit tests.

### Model catalog (`State/MockCatalogData.swift`)
Static array of `ModelCatalogItem` structs. Focused test set of 16 entries across 3 families: Gemma 4, Qwen 3.5, and LFM 2.5 (GGUF + MLX variants selected for iPhone edge testing). Capability flags (`supportsVision`, `supportsToolCalling`, `isThinkingModel`, `supportsReasoning`) should reflect runtime reality in this app, not only upstream model card claims.

`ModelCatalogItem` also derives per-model input categories for UI disclosure: `sourceInputCategories` (what the upstream model supports) and `runtimeInputCategories` (what this app currently accepts). Example: GGUF vision-family entries may show source `Text + Image` but runtime `Text` when the current llama.cpp integration path is text-only.

`supportsReasoning` and `isThinkingModel` are distinct flags: `isThinkingModel` means the model uses a native `<think>…</think>` streaming block (e.g. Qwen 3); `supportsReasoning` is a softer capability label.

Voice models should only be cataloged when there is a fully wired inference/runtime path for them. `VoiceInteractionController` itself uses iOS STT/TTS and is independent from chat model inference.

### GGUF vs MLX model storage
- **GGUF** models are downloaded to the app's Documents directory via `URLModelDownloadService`. `InstalledModel.localPath` (and `fileURL`) points to the `.gguf` file on disk.
- **MLX** models are downloaded to the system caches directory by the HuggingFace Hub library. `InstalledModel.localPath` is not used; the runtime loads from `ModelCatalogItem.mlxModelID` (a HF repo ID string like `"mlx-community/gemma-4-e2b-it-4bit"`).

### Model catalog IDs are deterministic
`ModelCatalogItem.id` is a UUID v5 derived from `"\(displayName)::\(variant)"`. **Do not rename `displayName` or `variant` of an existing catalog entry** — doing so generates a new UUID, orphaning any persisted `InstalledModel` records that reference the old ID.

### Voice layer (`Services/Voice/`)
`VoiceInteractionController` is a `@MainActor ObservableObject` wrapping `SFSpeechRecognizer` (STT) and `AVSpeechSynthesizer` (TTS). It exposes `transcript`, `isListening`, and `isSpeaking` as `@Published` state. Requires microphone + speech recognition permissions at runtime. This path is currently independent from GGUF/MLX chat inference models.

### Search layer (`Services/Search/`)
`SearchGateway` protocol with four implementations: Tavily, Brave, Serper, and a passthrough custom gateway. `SearchGatewayFactory` picks the active provider from `AppSettings`. API keys are stored in app settings (not Keychain). The custom gateway option is for user-operated compatible POST endpoints; the iOS app does not ship or require a backend service.

### Agentic search flow
Tool-calling models (`supportsToolCalling`) use a two-pass inference loop: the model first receives the user message **without** search results and decides whether to emit a `<tool_call>` for `web_search`. If `StreamProcessor` yields a `.toolCall` event, `ChatView` executes the search via `SearchGateway`, then re-invokes inference with the search context injected. Non-tool-calling models fall back to upfront search (auto-detect or user toggle). The `liveSearchEnabled` toggle always forces upfront search regardless of model capabilities.

### HuggingFace token storage
`HFTokenManager` stores the HF token in the iOS **Keychain** (not UserDefaults). Used by `ModelDownloadService` to add `Authorization: Bearer` headers for gated model downloads, and by `MLXRuntime` when building the `HubApi` for MLX model loading.

### Key wiring points
- `LocalAIEdgeApp.swift` (@main): injects `AppStateStore` and `AuthStateStore` into the environment, gates `RootView` behind auth.
- `ChatView.swift`: selects inference backend per model, drives the streaming loop by consuming `StreamEvent` values from `StreamProcessor`. Handles `.textDelta` (batched UI updates), `.thinkingDelta`/`.thinkingDone` (routed to `store.updateMessageThinking`), and `.toolCall` (triggers agentic search re-invocation).
- `ModelLibraryView.swift`: triggers downloads via `ModelDownloadService`, updates progress through `AppStateStore.updateInstallProgress()`.
- Cross-tab navigation uses `SelectedTabKey` `EnvironmentKey` — inject `@Environment(\.selectedTab)` and write to switch tabs without tight coupling.

## Adding a New Model to the Catalog

1. Add a `static let url` constant in the URL section of `MockCatalogData.swift`.
2. Add a `ModelCatalogItem(...)` entry in `items`. Use `supportsVision: true` only if the model has a vision encoder in its weights. Use `supportsToolCalling: true` only if the model has native `<tool_call>` or equivalent tokens in its chat template (not just prompt-level function calling).
3. Qwen 3 models always get `isThinkingModel: true` (native `/think`/`/no_think` switches).
4. Models over ~4 GB should not set `recommendedForIPhone: true`.
5. MLX models require `runtimeType: .mlx` and a `mlxModelID` string (HF repo ID). GGUF models require `runtimeType: .gguf` and a `downloadURL`.

## llama.cpp xcframework

The pre-built xcframework at `Vendor/build-apple/llama.xcframework` is vendored in-repo and linked directly via `project.yml` (`embed: true`, `codeSign: false`). Current `Info.plist` includes `ios-arm64` and `ios-arm64_x86_64-simulator` slices. Do not replace or update the xcframework without rebuilding all test targets.

## Gotchas

- **Gemma 4 thinking token format**: Gemma 4 models use `<|channel>thought\n...<channel|>` tokens for their thinking/reasoning block, NOT `<think>` tags. The app's `StreamProcessor` only detects `<think>`, `<thinking>`, `<reasoning>` tags. Therefore Gemma 4 thinking output renders as raw inline text — it is NOT routed to `.thinkingDelta` events. `isThinkingModel: false` is correct for Gemma 4 in the catalog. To fix this properly, add `<|channel>thought` / `<channel|>` detection to `StreamProcessor`.
- **Qwen 3.5 models are VLMs**: All Qwen 3.5 sizes (0.8B–9B) have a vision encoder. They accept `image_url` inputs and report VideoMME benchmark scores. In the MLX app, image input works via `VLMModelFactory`. Context is 256K tokens (262,144), not 32K.
- **Gemma 4 context**: Gemma 4 E2B and E4B support 128K tokens in context (not 32K as previously documented). The MLX runtime exposes the full context via the model weights.
- **LFM2.5 VL tool calling is text-only**: Per the official docs, `LFM2.5-VL-1.6B` supports tool calling for text-only inputs. Tool calls will not fire when the message content includes an image.
- **LFM2.5-1.2B-Thinking is a separate model**: The `LFM2.5-1.2B-Instruct` model does NOT have a thinking mode. Thinking is available only in `LFM2.5-1.2B-Thinking` (a distinct model variant not in the catalog). Do not set `isThinkingModel: true` for the Instruct variant.
- **`PromptRenderer` dynamic budget**: `maxPromptTokens = max(256, nCtx - maxGeneratedTokens - 64)`. On a 2048 n_ctx device in search mode, this floors at 256 tokens. Do not hardcode prompt limits.
- **Context reuse**: `LocalLlamaRuntime.ensureContext()` reloads when `maxGeneratedTokens` changes (search vs. chat mode). Switching between modes triggers a full model reload.
- **MLX on simulator**: `#if canImport(MLXLLM) && !targetEnvironment(simulator)` guards all MLX calls. GGUF models still work in simulator.
- **Sign in with Apple**: `com.apple.developer.applesignin` entitlement is currently commented out in `.entitlements` to support free developer accounts. Re-enable it when targeting a paid team.
- **`project.yml` is the source of truth**: Running `xcodegen generate` overwrites `.xcodeproj`. Stage `project.yml` changes before generating.
- **Design system is dark-mode only**: `AppTheme` has no light-mode variants. Do not add `colorScheme`-conditional logic — the app enforces dark mode at the window level.
- **`ChatMessage.Role.search` is deprecated**: Citations live on `ChatMessage.citations: [SearchCitation]`. The `.search` role creates orphaned messages if inference is cancelled. Render citations as a "Sources" footer on the assistant bubble instead (see `TODOS.md`).
- **Image attachments are downsampled before inference**: `ChatComposerView` bounds JPEG encoding to prevent OOM. Do not pass raw `UIImage` to the inference service.
- **MLX GPU cache**: `MLXRuntime` unloads the previous model and calls `GPU.clearCache()` before loading a new one. Vision models get a larger cache limit (768 MB vs 512 MB) to accommodate the SigLIP tower.
