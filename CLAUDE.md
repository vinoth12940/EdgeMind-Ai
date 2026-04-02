# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
Vendor/build-apple/      # Pre-built llama.cpp xcframework (b8354, arm64 only)
backend/search-gateway/  # Optional Node.js/Express proxy (Tavily) for self-hosted search
```

## Architecture

### State layer (`State/`)
`AppStateStore` is an `@Observable` class injected at the SwiftUI root and holds all runtime state: catalog, installed models, chat sessions, settings. All mutations go through its `func` methods (not direct property writes). `AuthStateStore` is a separate `@Observable` for auth state (Apple ID / local / guest / device biometrics).

Persistence uses `UserDefaults` via JSON encoding. Images in chat history are sanitized before persistence (`sanitizedSessionForPersistence`) to avoid oversized writes (threshold: 600 KB per image).

`AppStateStore.reconcileInstalledFiles()` is called at launch to reconcile GGUF files present on disk with persisted `InstalledModel` records — it scans the models directory and calls `markInstallCompleted` for any matching files.

### Inference layer (`Services/Inference/`)
Two concrete inference backends behind the `InferenceService` protocol:

- **`LocalLlamaInferenceService`** — GGUF models via llama.cpp C API. Contains the `PromptRenderer` enum (token budget calculation, HTML stripping, chat-turn assembly). `PromptRenderer` is `internal` for testability. Does **not** support image input — throws if `imageData != nil`.
- **`MLXInferenceService`** — MLX models via `mlx-swift-examples` (MLXLLM, VLMModelFactory). Falls back to a plain prompt string for models without a chat template. Only loads the SigLIP vision tower when `imageData != nil && supportsVision` to prevent OOM on 8 GB devices.

Both backends use **singleton actors** (`LocalLlamaRuntime.shared`, `MLXRuntime.shared`) for thread-safe C/MLX interop. The actors hold the loaded model context and reuse it across calls when model path and `maxGeneratedTokens` are unchanged.

`ChatView` holds two `@State` inference service instances and selects between them at call time via `inferenceServiceForModel(_:)` which checks `runtimeType == .mlx`.

**`DeviceCapabilityService`** reads `hw.machine` via `sysctlbyname` to select:
- `n_ctx`: 2048 (A14/iPhone 12), 4096 (A15/A16), 8192 (A17/A18/iPad/Simulator)
- Flash attention: disabled on A14, enabled on A15+

`maxGeneratedTokens` is 1024 for chat and 2048 when a `SearchContext` is present.

`AssistantResponseSanitizer.clean()` (in `InferenceService.swift`) strips model-specific tokens (`<think>`, `<|im_end|>`, `[INST]`, etc.) from streamed output before display. Note: `<think>` blocks are **extracted live during streaming** by `ChatView` (via `updateMessageThinking`) and stored in `ChatMessage.thinkingContent` — they are not stripped here.

`MockInferenceService` (in `Services/Inference/`) provides a stub for SwiftUI previews and unit tests.

### Model catalog (`State/MockCatalogData.swift`)
Static array of `ModelCatalogItem` structs. 35 entries across 4 families: Gemma, Qwen, LFM, Kokoro. Capability flags (`supportsVision`, `supportsToolCalling`, `isThinkingModel`, `supportsReasoning`) reflect actual model card specs — only set when the model has native tokens in its chat template or vision encoder in its weights. Do not add flags speculatively.

`supportsReasoning` and `isThinkingModel` are distinct flags: `isThinkingModel` means the model uses a native `<think>…</think>` streaming block (e.g. Qwen 3); `supportsReasoning` is a softer capability label.

Models with `primaryUse: .voice` (Kokoro, LFM2.5 Audio) are filtered out of the chat model picker but appear in the Model Library.

### GGUF vs MLX model storage
- **GGUF** models are downloaded to the app's Documents directory via `URLModelDownloadService`. `InstalledModel.localPath` (and `fileURL`) points to the `.gguf` file on disk.
- **MLX** models are downloaded to the system caches directory by the HuggingFace Hub library. `InstalledModel.localPath` is not used; the runtime loads from `ModelCatalogItem.mlxModelID` (a HF repo ID string like `"mlx-community/gemma-3n-E2B-it-bf16"`).

### Model catalog IDs are deterministic
`ModelCatalogItem.id` is a UUID v5 derived from `"\(displayName)::\(variant)"`. **Do not rename `displayName` or `variant` of an existing catalog entry** — doing so generates a new UUID, orphaning any persisted `InstalledModel` records that reference the old ID.

### Voice layer (`Services/Voice/`)
`VoiceInteractionController` is a `@MainActor ObservableObject` wrapping `SFSpeechRecognizer` (STT) and `AVSpeechSynthesizer` (TTS). It exposes `transcript`, `isListening`, and `isSpeaking` as `@Published` state. Requires microphone + speech recognition permissions at runtime. Voice models (Kokoro, LFM2.5 Audio) are separate from voice I/O — they are MLX inference models for on-device TTS, not used by `VoiceInteractionController`.

### Search layer (`Services/Search/`)
`SearchGateway` protocol with four implementations: Tavily, Brave, Serper, and a passthrough custom gateway. `SearchGatewayFactory` picks the active provider from `AppSettings`. API keys are stored in app settings (not Keychain). The `backend/search-gateway/` directory is an optional Node.js/Express proxy that forwards to Tavily — used when `AppSettings.customGatewayURL` points at it.

### HuggingFace token storage
`HFTokenManager` stores the HF token in the iOS **Keychain** (not UserDefaults). Used by `ModelDownloadService` to add `Authorization: Bearer` headers for gated model downloads, and by `MLXRuntime` when building the `HubApi` for MLX model loading.

### Key wiring points
- `LocalAIEdgeApp.swift` (@main): injects `AppStateStore` and `AuthStateStore` into the environment, gates `RootView` behind auth.
- `ChatView.swift`: selects inference backend per model, drives the streaming loop via `Task { for await token in stream }` with 80 ms batched UI updates, and extracts `<think>` blocks live via `store.updateMessageThinking(...)`.
- `ModelLibraryView.swift`: triggers downloads via `ModelDownloadService`, updates progress through `AppStateStore.updateInstallProgress()`.
- Cross-tab navigation uses `SelectedTabKey` `EnvironmentKey` — inject `@Environment(\.selectedTab)` and write to switch tabs without tight coupling.

## Adding a New Model to the Catalog

1. Add a `static let url` constant in the URL section of `MockCatalogData.swift`.
2. Add a `ModelCatalogItem(...)` entry in `items`. Use `supportsVision: true` only if the model has a vision encoder in its weights. Use `supportsToolCalling: true` only if the model has native `<tool_call>` or equivalent tokens in its chat template (not just prompt-level function calling).
3. Qwen 3 models always get `isThinkingModel: true` (native `/think`/`/no_think` switches).
4. Models over ~4 GB should not set `recommendedForIPhone: true`.
5. MLX models require `runtimeType: .mlx` and a `mlxModelID` string (HF repo ID). GGUF models require `runtimeType: .gguf` and a `downloadURL`.

## llama.cpp xcframework

The pre-built xcframework at `Vendor/build-apple/llama.xcframework` is Mach-O arm64 only. It will not link for x86_64 simulator targets. The `project.yml` sets `codeSign: false` and `embed: true` for this dependency. Do not replace or update the xcframework without rebuilding all test targets.

## Backend Search Gateway (Optional)

`backend/search-gateway/` is a TypeScript/Express app. To run locally:

```bash
cd backend/search-gateway
npm install
cp .env.example .env   # add TAVILY_API_KEY
npm run dev            # default port 8787
```

Point `AppSettings.customGatewayURL` at `http://localhost:8787` in the app's Settings to use it.

## Gotchas

- **`PromptRenderer` dynamic budget**: `maxPromptTokens = max(256, nCtx - maxGeneratedTokens - 64)`. On a 2048 n_ctx device in search mode, this floors at 256 tokens. Do not hardcode prompt limits.
- **Context reuse**: `LocalLlamaRuntime.ensureContext()` reloads when `maxGeneratedTokens` changes (search vs. chat mode). Switching between modes triggers a full model reload.
- **MLX on simulator**: `#if canImport(MLXLLM) && !targetEnvironment(simulator)` guards all MLX calls. GGUF models still work in simulator.
- **Sign in with Apple**: `com.apple.developer.applesignin` entitlement is currently commented out in `.entitlements` to support free developer accounts. Re-enable it when targeting a paid team.
- **`project.yml` is the source of truth**: Running `xcodegen generate` overwrites `.xcodeproj`. Stage `project.yml` changes before generating.
- **Design system is dark-mode only**: `AppTheme` has no light-mode variants. Do not add `colorScheme`-conditional logic — the app enforces dark mode at the window level.
- **`ChatMessage.Role.search` is deprecated**: Citations live on `ChatMessage.citations: [SearchCitation]`. The `.search` role creates orphaned messages if inference is cancelled. Render citations as a "Sources" footer on the assistant bubble instead (see `TODOS.md`).
- **Image attachments are downsampled before inference**: `ChatComposerView` bounds JPEG encoding to prevent OOM. Do not pass raw `UIImage` to the inference service.
- **MLX GPU cache**: `MLXRuntime` unloads the previous model and calls `GPU.clearCache()` before loading a new one. Vision models get a larger cache limit (768 MB vs 512 MB) to accommodate the SigLIP tower.
