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
LocalAIEdgeAppTests/     # Unit test target (XCTest)
Vendor/build-apple/      # Pre-built llama.cpp xcframework (b8354, arm64 only)
```

## Architecture

### State layer (`State/`)
`AppStateStore` is an `@Observable` class injected at the SwiftUI root and holds all runtime state: catalog, installed models, chat sessions, settings. All mutations go through its `func` methods (not direct property writes). `AuthStateStore` is a separate `@Observable` for auth state (Apple ID / local / guest / device biometrics).

Persistence uses `UserDefaults` via JSON encoding. Images in chat history are sanitized before persistence (`sanitizedSessionForPersistence`) to avoid oversized writes.

### Inference layer (`Services/Inference/`)
Two concrete inference backends behind the `InferenceService` protocol:

- **`LocalLlamaInferenceService`** — GGUF models via llama.cpp C API. Contains the `PromptRenderer` enum (token budget calculation, HTML stripping, chat-turn assembly). `PromptRenderer` is `internal` for testability.
- **`MLXInferenceService`** — MLX models via `mlx-swift-examples` (MLXLLM, VLMModelFactory). Falls back to a plain prompt string for models without a chat template.

Both backends use **singleton actors** (`LocalLlamaRuntime.shared`, `MLXRuntime.shared`) for thread-safe C/MLX interop. The actors hold the loaded model context and reuse it across calls when model path and `maxGeneratedTokens` are unchanged.

**`DeviceCapabilityService`** reads `hw.machine` via `sysctlbyname` to select:
- `n_ctx`: 2048 (A14/iPhone 12), 4096 (A15/A16), 8192 (A17/A18/iPad/Simulator)
- Flash attention: disabled on A14, enabled on A15+

`maxGeneratedTokens` is 1024 for chat and 2048 when a `SearchContext` is present.

`AssistantResponseSanitizer.clean()` (in `InferenceService.swift`) strips model-specific tokens (`<think>`, `<|im_end|>`, `[INST]`, etc.) from streamed output before display.

### Model catalog (`State/MockCatalogData.swift`)
Static array of `ModelCatalogItem` structs. 35 entries across 4 families: Gemma, Qwen, LFM, Kokoro. Capability flags (`supportsVision`, `supportsToolCalling`, `isThinkingModel`) reflect actual model card specs — only set when the model has native tokens in its chat template or vision encoder in its weights. Do not add flags speculatively.

Models with `primaryUse: .voice` (Kokoro, LFM2.5 Audio) are filtered out of the chat model picker but appear in the Model Library.

### Search layer (`Services/Search/`)
`SearchGateway` protocol with four implementations: Tavily, Brave, Serper, and a passthrough custom gateway. `SearchGatewayFactory` picks the active provider from `AppSettings`. API keys are stored in app settings (not Keychain).

### Key wiring points
- `LocalAIEdgeApp.swift` (@main): injects `AppStateStore` and `AuthStateStore` into the environment, gates `RootView` behind auth.
- `ChatView.swift`: calls `AppStateStore` to append messages, drives the streaming loop via `Task { for await token in stream }`.
- `ModelLibraryView.swift`: triggers downloads via `ModelDownloadService`, updates progress through `AppStateStore.updateInstallProgress()`.

## Adding a New Model to the Catalog

1. Add a `static let url` constant in the URL section of `MockCatalogData.swift`.
2. Add a `ModelCatalogItem(...)` entry in `items`. Use `supportsVision: true` only if the model has a vision encoder in its weights. Use `supportsToolCalling: true` only if the model has native `<tool_call>` or equivalent tokens in its chat template (not just prompt-level function calling).
3. Qwen 3 models always get `isThinkingModel: true` (native `/think`/`/no_think` switches).
4. Models over ~4 GB should not set `recommendedForIPhone: true`.

## llama.cpp xcframework

The pre-built xcframework at `Vendor/build-apple/llama.xcframework` is Mach-O arm64 only. It will not link for x86_64 simulator targets. The `project.yml` sets `codeSign: false` and `embed: true` for this dependency. Do not replace or update the xcframework without rebuilding all test targets.

## Gotchas

- **`PromptRenderer` dynamic budget**: `maxPromptTokens = max(256, nCtx - maxGeneratedTokens - 64)`. On a 2048 n_ctx device in search mode, this floors at 256 tokens. Do not hardcode prompt limits.
- **Context reuse**: `LocalLlamaRuntime.ensureContext()` reloads when `maxGeneratedTokens` changes (search vs. chat mode). Switching between modes triggers a full model reload.
- **MLX on simulator**: `#if canImport(MLXLLM) && !targetEnvironment(simulator)` guards all MLX calls. GGUF models still work in simulator.
- **Sign in with Apple**: `com.apple.developer.applesignin` entitlement is currently commented out in `.entitlements` to support free developer accounts. Re-enable it when targeting a paid team.
- **`project.yml` is the source of truth**: Running `xcodegen generate` overwrites `.xcodeproj`. Stage `project.yml` changes before generating.
