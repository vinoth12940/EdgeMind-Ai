# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **`AGENTS.md` is the detailed source of truth** for architecture, per-model runtime facts, and gotchas. This file is the fast-start summary; read `AGENTS.md` before touching inference, the model catalog/audit system, or store-facing/privacy code. (The `CLAUDE.md` one directory up describes an unrelated project, WonderSprout — ignore it here.)

## What this is

**Edge Mind Ai** is a privacy-first, on-device iOS/iPadOS chat app (SwiftUI, iOS 17+). It runs local LLM/VLM models across **four runtimes** — llama.cpp (GGUF), Apple MLX, LiteRT-LM, and Apple Foundation Models — with optional user-configured web search. There is **no backend**; all inference is local, and the only outbound calls are the user's search gateway and HuggingFace model downloads.

## Build & Test

The Xcode project is generated from `project.yml` via **XcodeGen** — `project.yml` + Swift source are the source of truth. **Never edit `.xcodeproj` directly.** Run `xcodegen generate` after editing `project.yml` (it overwrites `.xcodeproj`, so stage `project.yml` first). There is no separate linter — the Xcode compiler is the type checker.

```bash
# Regenerate project after editing project.yml
xcodegen generate

# Build for simulator (GGUF only — MLX/LiteRT/FoundationModels do NOT run in simulator)
xcodebuild -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO build

# Run all unit tests (simulator)
xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max'

# Run a single test class
xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max' \
  -only-testing EdgeMindAiTests/DeviceCapabilityTests

# Verify documentation freshness against codebase state
python3 scripts/verify_docs_freshness.py
xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max' \
  -only-testing EdgeMindAiTests/DocumentationFreshnessTests

# Build for a connected device (MLX/LiteRT require real Apple Silicon hardware)
xcodebuild -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -destination 'id=YOUR_DEVICE_UDID' -allowProvisioningUpdates build
```

The simulator excludes `x86_64` (`EXCLUDED_ARCHS[sdk=iphonesimulator*]`), so an Apple Silicon host is required. MLX/LiteRT code is compiled out of the simulator via `#if canImport(MLXLLM) && !targetEnvironment(simulator)` — keep those guards intact.

## Architecture (big picture)

Layout: `EdgeMindAi/{App, Models, State, Services, Features, DesignSystem, Resources}`; tests in `EdgeMindAiTests/` (XCTest). Vendored native deps live in `Vendor/build-apple/` (llama.cpp xcframework) and `Vendor/LiteRT-LM/` (local Swift package).

- **State** — `AppStateStore` (`@Observable`, injected at the SwiftUI root) holds all runtime state: catalog, installed models, chat sessions, settings. **All mutations go through its `func` methods**, not direct property writes. `AuthStateStore` is a separate `@Observable` for auth (Apple ID / local / guest / device biometrics). Persistence is `UserDefaults` + JSON; chat images are sanitized before persistence to avoid oversized writes.

- **Inference** — Four backends behind the `InferenceService` protocol, selected by `ModelCatalogItem.RuntimeType`: `LocalLlamaInferenceService` (GGUF, text-only, holds `PromptRenderer`), `MLXInferenceService` (MLX text+vision), `LiteRTInferenceService` (Gemma 4 E2B/E4B), `AppleFoundationModelService` (Apple Intelligence, no weights). `ChatView` holds one `@State` instance per runtime and routes via `inferenceServiceForModel(_:)`, calling `RuntimeMemoryCoordinator.prepareForRuntime(...)` first to free the prior runtime's memory (runtimes must not co-occupy memory).

- **`InferenceBudget` is the single source of truth for context/token limits** — never hardcode prompt/context sizes. Device tiers come from `DeviceTier` (`compact`/`standard`/`pro`/`ultra` by RAM); GGUF `n_ctx` and flash-attention gating come from `DeviceCapabilityService` (reads `hw.machine` via `sysctlbyname`).

- **Stream processing** — `StreamProcessor` (an `actor`) parses raw `AsyncStream<String>` into typed `StreamEvent`s (`.textDelta`, `.thinkingDelta/.thinkingDone`, `.toolCall`, `.done`): extracts `<think>`-style reasoning blocks and `<tool_call>` blocks (including Gemma's non-JSON tool-call format). `ChatView.runToolLoop` drives the agentic tool loop (bounded at `ToolRegistry.maxIterations = 3`); tools live in `Services/Tools/` behind the `Tool` protocol + `ToolRegistry`, all on-device except `web_search`.

- **Catalog vs. Profile (critical distinction)** — `State/MockCatalogData.swift` holds *advertised* capability (`supportsVision`, `supportsToolCalling`, `isThinkingModel`, …). `EdgeMindAi/Resources/RuntimeProfiles.json` holds *verified* capability per model. `ModelRuntimeResolver.resolve(...)` merges them and flags `isMismatch` when the catalog claims something the profile hasn't verified. **When they disagree, trust the profile for runtime behavior.** `ModelAuditRunner`/`HeadlessModelAuditLauncher` probe installed models and write results back. See the `raiSafety` audit note in `AGENTS.md` + `docs/MODEL_AUDIT_HANDOFF.md` — it's a high-impact, historically brittle refusal checker; keep `ResponsibleAIGuardTests` green when touching it.

- **Deterministic IDs** — `DeterministicID` generates namespaced UUID v5 IDs from string inputs (e.g. `ModelCatalogItem.id = "displayName::variant"`). **Renaming those inputs mints a new UUID and orphans persisted records** — don't rename inputs of existing entries.

## When editing common things

- **Adding a catalog model**: add the entry in `MockCatalogData.swift` with the correct `runtimeType`, **and** a matching `RuntimeProfile` in `RuntimeProfiles.json` (same `catalogID`) — without it, every claimed capability shows as an unverified mismatch. Full checklist in `AGENTS.md` → "Adding a New Model to the Catalog".
- **Updating catalog, project versions, or runtime profiles**: whenever `MockCatalogData.swift`, `project.yml`, or `RuntimeProfiles.json` change, developers/agents must update documentation and run `python3 scripts/verify_docs_freshness.py` and `xcodebuild test -only-testing EdgeMindAiTests/DocumentationFreshnessTests` before committing.
- **Design system**: `AppTheme` defines light + dark variants for every color; appearance is set once at the window root via `.preferredColorScheme`. Don't add per-view `colorScheme` conditionals — extend `AppTheme`.
- **Store / privacy / networking**: this app ships **no telemetry, analytics, or cloud sync**, and requires no remote account (guest must always reach chat). New networking must be opt-in and user-facing. Read `AGENTS.md` → "Release & App Store submission" and `APP_STORE_REVIEW_NOTES.md` before store-facing changes.
