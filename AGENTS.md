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
  -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Run unit tests (simulator)
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max'
```

### Run a single test class
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max' \
  -only-testing EdgeMindAiTests/DeviceCapabilityTests
```

### Documentation freshness verification
Whenever `MockCatalogData.swift`, `project.yml`, or runtime profiles change, developers and agents must run the freshness verification script before committing:
```bash
python3 scripts/verify_docs_freshness.py
```
Or run the dedicated unit test suite:
```bash
xcodebuild test \
  -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max' \
  -only-testing EdgeMindAiTests/DocumentationFreshnessTests
```

Note: the simulator excludes `x86_64` (`EXCLUDED_ARCHS[sdk=iphonesimulator*]: x86_64` in `project.yml`) — Apple Silicon hosts only.

No linter is configured — the project uses the Xcode compiler for type checking.

## Release & App Store submission

- **Release workflow:** use the `/app-store-release` skill (`.claude/skills/app-store-release/SKILL.md`). `scripts/asc_submit.py --check` reports live build/version state; without flags it attaches the build and submits for review. Credentials load from `~/private_keys/asc.env` (never committed).
- **Current App Store state (September 16, 2026):** version `0.3.3`, build `10` is the current release train. It carries the whole 0.3.1 feature set (regenerate/edit, export, model suggestions, memory, document library, Share Extension, widgets, Shortcuts answers), Apple Intelligence vision and tool calling on iOS 27, on-device OCR, relevance-based document excerpting and LiteRT prompt budgeting, **plus 28 fixes from a whole-codebase audit** (tool calling no longer fires on greetings; Apple Intelligence and Gemma/LFM reach the document library; a frozen-UI Markdown loop; PDF export pagination; answer-version and regenerate data loss; Keychain credential loss on launch; share double-import; MLX install-state and cache path; LiteRT search grounding and prompt budget; light-mode contrast). Version `0.3.2` build `9` was **approved and is live** (`READY_FOR_SALE`), so its train is closed. Version `0.3.1` build `7` and `0.3.0` build `6` were approved earlier, and `0.2.0` build `5` was submitted on July 8, 2026. Both numbers live in `project.yml`; bump them there, then run `xcodegen generate` **and commit the regenerated `EdgeMindAi.xcodeproj/project.pbxproj`** before archiving — the build number only reaches the build through regeneration. `MARKETING_VERSION` is user-facing (`CFBundleShortVersionString`), `CURRENT_PROJECT_VERSION` is the build number (`CFBundleVersion`) and must increment on every new upload.
- **Signing / upload without an Xcode account:** `xcodebuild -exportArchive` with `destination: upload` requires an authenticated **Xcode** Apple Account and can only cloud-sign if that account already has a distribution certificate. Being signed into System Settings → Apple Account (iCloud) does **not** satisfy it (`defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists` shows whether Xcode has one). On September 16, 2026 Xcode had no account and the account had **no distribution certificate at all**, so export failed with `Failed to Use Accounts` / `No signing certificate "iOS Distribution" found` / `Cloud signing permission error`. The fix is `scripts/asc_signing.sh` (`bootstrap` → `export` → `upload`), which creates the distribution cert and the three `IOS_APP_STORE` profiles through the App Store Connect API key and uploads with `xcrun altool --upload-app --apiKey`. Two traps it handles: OpenSSL 3 PKCS#12 needs `-legacy` or macOS `security import` reports `MAC verification failed`, and the API's `profileContent` is **base64** and must be decoded before `security cms -D`.
- **Replacing a build already in review:** a version in `WAITING_FOR_REVIEW`/`IN_REVIEW` cannot have its build swapped. Cancel the submission first (`PATCH /v1/reviewSubmissions/{id}` with `{"attributes":{"canceled":true}}`); the version then reads `DEVELOPER_REJECTED` and the next `scripts/asc_submit.py` run attaches the new build and submits normally. Prefer this over shipping a known-bad build.
- **Bundle ID:** `com.vinothrajalingam.EdgeMindAi` (team `43NV5DTHKG`, paid Apple Developer Program); the app-extension targets use `.Share` and `.Widget`. TestFlight is available; Sign-in-with-Apple can be re-enabled (it's currently off only because v0.1.0 doesn't need cloud auth — see Gotchas).
- **Submission docs to read before touching store-facing or privacy-sensitive areas:**
  - `APP_STORE_LISTING.md` — paste-ready App Store Connect metadata (title, subtitle, description, categories, privacy policy URL).
  - `APP_STORE_REVIEW_NOTES.md` — reviewer guidance (no remote auth, Apple Intelligence as the no-download test model, physical-device requirement for MLX, China mainland removed from availability for this version).
  - `docs/privacy.html` — the hosted privacy policy referenced by the listing.
- **Export compliance:** The app does not implement proprietary, custom, or non-standard encryption. It uses Apple/system-provided security such as HTTPS/TLS via iOS frameworks and Keychain storage. In App Store Connect's "App Encryption Documentation" flow, choose **"None of the algorithms mentioned above"** for "What type of encryption algorithms does your app implement?" The project also sets `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` in `project.yml`; do not remove it unless the app starts implementing non-exempt encryption.
- **ASC API gotcha:** `GET /v1/appStoreVersions` (collection) now returns 403 `FORBIDDEN_ERROR`; create the version directly with `POST /v1/appStoreVersions` or read it via `GET /v1/apps/{id}/appStoreVersions`.
- **Build selection in App Store Connect:** Uploading a new build does not automatically replace the build selected on the App Store version page. After upload processing completes, go to the version distribution page, remove the older selected build if needed, click **Add Build**, choose the newest build, click **Done**, then **Save**. Alternatively, use the App Store Connect REST API (`PATCH /v1/appStoreVersions/{id}/relationships/build`) to attach the build programmatically — this is how v0.3.0 build 6 was submitted. On July 8, 2026, build `4` was still selected even after build `5` uploaded; build `5` had to be manually selected and saved before review submission.
- **LiteRT symbols:** `CLiteRTLM.framework` is vendored through `Vendor/LiteRT-LM` and needs its dSYM packaged for App Store uploads. `project.yml` contains the `Generate CLiteRTLM dSYM` post-build script. If Apple reports `CLiteRTLM.framework missing dSYM UUID`, verify the archive contains `dSYMs/CLiteRTLM.framework.dSYM` and that its UUID matches the embedded framework before uploading again.
- **Upload verification:** Treat Xcode's `UPLOAD SUCCEEDED with no errors` as upload completion, but still check App Store Connect/TestFlight for processing state. A build should show **Complete** (`processingState: VALID` via the API) and **Ready to Submit** before it is selected on a distribution page. For v0.3.0, build `6` was the correct submitted build (Delivery UUID `91691958-6a5d-489d-91af-47122727f453`). For v0.2.0, build `5` was the correct submitted build; build `3` had missing compliance and build `4` was superseded.
- **Extended attributes gotcha:** Before archive/device builds, run `xattr -cr EdgeMindAi Vendor` to clear `com.apple.provenance` extended attributes. Without this, `codesign` fails with "resource fork, Finder information, or similar detritus not allowed".
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

### Answer versions and edit (v0.3.1)
`ChatMessage.versions: [AnswerVersion]` holds alternate answers for a message and `selectedVersion` indexes the one currently mirrored into the message's top-level fields (`text`, `thinkingContent`, `stats`, `toolActivities`, `citations`, durations). An empty `versions` array means the message has exactly one implicit version, so old persisted data decodes unchanged. Rules:
- **Every existing reader keeps using the top-level fields** — `mirrorSelectedVersion()` keeps them in sync, and `AppStateStore`'s `update*` mutations write to the selected version *and* the mirror.
- The first regenerate snapshots the current answer as version 0. `AppStateStore.maxAnswerVersions` (5) caps a message; a 6th regenerate evicts the oldest **non-selected** version.
- Only the selected version is sent to models as history.
- Regenerate targets are `TurnRequest.Target.regenerate(assistantMessageID:model:)`; `StoreTurnOutput.Mode.regenerate` writes the new answer into a new version instead of appending a message, and re-derives the prompt/image from the preceding user message. The optional `model` overrides the default for that turn only.
- Edit-and-resend is `AppStateStore.removeMessagesForEdit(from:in:)` (user messages only) followed by a normal `.newMessage` send with the returned attachments. The UI confirms first because later replies are removed.
- Sanitizers copy and mutate (`sanitizedMessageForInMemory`/`sanitizedMessageForPersistence` trim every version too); they must never rebuild a message field by field.

### Personal memory (v0.3.1)
`MemoryItem` (≤200 characters) is persisted by `MemoryStore` (`@MainActor @Observable`) under the UserDefaults key `persistedMemoryItems`, capped at `MemoryStore.maxItems` (50; the oldest is evicted). `MemoryStore.promptSection(budgetTokens:)` renders enabled items **newest-first** into a `# About the user` section, stopping before the budget; `InferenceBudget.memoryTokenBudget(for:tier:)` is 150 / 300 / 500 tokens for device-safe contexts of ≤2048 / 4096 / larger. `ChatTurnEngine` injects the section when `AppSettings.memoryEnabled` (default on) and records `ChatMessage.memoryCount` for the "Using N memories" chip. The composer detects "remember that …", "remember I …", and "don't forget …" with `MemoryPhraseDetector` and offers Save / Don't save; the turn proceeds either way. The Memory screen lives in Settings → AI Configuration → Memory. Memories never leave the device.

### Widgets (v0.3.1)
`EdgeMindWidget` is a WidgetKit `app-extension` target with a static, `.never`-refreshing timeline and **no shared data** — it never reads chats, memories, or the document library. Families: `systemSmall` (Ask), `systemMedium` (Ask / Voice / Camera), and `accessoryCircular` (Ask). Every control is a `Link` to `edgemindai://ask?mode=text|voice|camera`, handled by `DeepLinkRouter`.

### Share Extension, deep links, and Shortcuts (v0.3.1)
- **App Group** `group.com.vinothrajalingam.EdgeMindAi` (entitlement on both the app and `EdgeMindShare`). Only the share inbox lives there (`AppGroup.containerURL/Inbox`); chat sessions, settings, and installed models stay in the app's own container.
- **Share inbox** — `ShareInbox` reads/writes `Inbox/<uuid>/payload.json` plus an optional copied file. `SharePayload` carries `action` (summarize/explain/ask), `question`, `text`, and `fileName`. `ShareInboxProcessor` drains items on launch and on `scenePhase == .active`: files import into the document library and inline their extracted text, images/text attach to a new chat, and summarize/explain auto-send. Items older than 24 hours are discarded. The extension runs **no** inference or indexing (iOS caps extensions near 120 MB); shared URLs are passed as text and never fetched.
- **`EdgeMindShare`** is an `app-extension` target in `project.yml` sharing `Services/Share/AppGroup.swift` and `ShareInbox.swift` with the app. It writes the payload, then opens `edgemindai://share/<id>` through the responder chain.
- **URL scheme `edgemindai://`** (registered via the partial `EdgeMindAi/Info.plist`) is parsed by `DeepLinkRouter.route(for:)` into `.ask(mode:)`, `.share(id)`, `.settingsMemory`, or `.settingsDocuments`. `DeepLinkCoordinator` (injected at the app root, consumed once) carries the route; `RootView` switches to Settings, `SettingsView` pushes the section, and `ChatView` handles ask/share.
- **Shortcuts** — `AskDefaultLocalModelIntent` has `openAppWhenRun = false` and conforms to `ReturnsValue<String> & ProvidesDialog`. It calls `ChatTurnEngine.answerHeadless(prompt:)`, which runs the normal pipeline into a `CollectingTurnOutput` (writing a real chat titled from the prompt) and is allowed only for Apple Intelligence or a ready model whose parsed disk size is ≤ 2 GB and which passes `AvailableMemoryGuard`; otherwise it throws `.needsApp`, the intent saves the handoff, and the dialog tells the user to open the app. A 120-second timeout stops the turn and returns partial text. The engine is reached through `AppServices.shared`, created by `EdgeMindAiApp`.

### Apple Foundation Models on iOS 27 (v0.3.2)
WWDC26 opened the Foundation Models framework: a public **`LanguageModel`** protocol plus **`LanguageModelExecutor`**, with `SystemLanguageModel`, `PrivateCloudComputeLanguageModel`, Core AI and MLX as providers. Everything is **`@available(iOS 27.0, *)`**, so the app keeps its iOS 17 deployment target by gating each use.
- **Runtime capability, not version guessing.** `AppleFoundationModelService.supportsVision` / `.supportsToolCalling` read `SystemLanguageModel.default.capabilities` rather than assuming from the OS version.
- **The system model now takes images.** `visionPrompt(text:imageData:)` builds a multimodal `Prompt` with `Attachment<ImageAttachmentContent>` (which conforms to `PromptRepresentable`, so it composes inside the `@PromptBuilder` closure). Note `Transcript.Prompt` is the *transcript-side* type and is **not** what `respond(to:)` accepts.
- **The composer gates on capability too.** `ChatInputCapability.acceptsImage` returns false for `.foundationModels` when the OS/runtime can't do vision, so iOS 17-26 never offers an image button that would fail. `defaultInputModes` includes `.image` for vision-capable runtimes (MLX, LiteRT, and now Foundation Models — never GGUF, whose llama.cpp path is text-only).
- **Verify before flipping the profile.** `AppleFoundationVisionProbe` (DEBUG-only) is the evidence gate for `verifiedVision`:
  ```bash
  DEVICECTL_CHILD_FM_VISION_PROBE=1 xcrun devicectl device process launch --console \
    --device <udid> com.vinothrajalingam.EdgeMindAi
  ```
  `devicectl` intercepts dash-prefixed arguments, so the env var is the reliable trigger. Verified PASS on iPhone 17 Pro / iOS 27.0 (`supportsVision=true`, `supportsToolCalling=true`).

### Tool calling on Apple Intelligence (v0.3.2)
The iOS 27 system model **does** follow the app's `<tool_call>` convention, so it joins the existing agentic loop instead of needing a second, native tool path. Two things had to be true — both are now verified:
1. **`AppleFoundationModelService` must route through `StreamProcessor`.** It previously handed its text straight to the UI, so `<tool_call>` blocks were never parsed and the loop could never fire for this runtime. `generateStream` now wraps its single response in a `StreamProcessor`, giving it the same tool-call/think handling as GGUF and MLX.
2. **`arguments` must reach tools as arguments, not as the whole payload.** `StreamProcessor.parseToolCall` used to return the entire `{"name":…,"arguments":…}` JSON, which broke tools like `calculate` (they look for their own keys). `StreamProcessor.argumentsJSON(from:)` now normalizes every shape models use:
   - nested object — `{"arguments": {"query": "x"}}`
   - JSON encoded as a string — `{"arguments": "{\"query\": \"x\"}"}`
   - **bare value** — `{"arguments": "47 * 89"}`, which is what Apple Intelligence emits; it passes through unchanged so each tool's raw-string fallback interprets it.
   - JSON-encoded scalars/arrays — `{"arguments": "\"6*7\""}` is unwrapped (quotes stripped) and `{"arguments": 5}` / `{"arguments": ["a"]}` are serialized instead of collapsing to `{}`.
   - **no `arguments` wrapper at all** — `{"name": "web_search", "query": "…"}` passes its remaining keys through, because several models (and the app's own legacy `web_search` fallback) express arguments flat. Returning `{}` here was a shipped regression: every such Liquid/LFM-format call failed with "Missing … argument".
   This matches the Gemma payload convention, which was already arguments-only.

   **Every tool extractor must tolerate flat, nested, JSON-string and bare-string input.** `SearchDocumentsTool.extractQuery` was the lone one missing the bare-string case, so Apple Intelligence document search *always* failed and the model told the user to upload the document. When adding a tool, cover all four shapes — and assert the **arguments** in tests, not just the tool name. The flat-payload regression stayed green for days because a test destructured `case .toolCall(let name, _)` and threw the arguments away.

Device evidence (iPhone 17 Pro / iOS 27.0, `FM_TOOL_PROBE=1`): the model emitted
`<tool_call>{"name": "calculate", "arguments": "47 * 89"}</tool_call>`.
Note it also hallucinated an answer afterwards — which is exactly why the tool loop
intercepts and re-invokes with the real result rather than trusting the model.
`StreamProcessorTests` locks the end-to-end path (payload → `.toolCall` → `CalculateTool` → 4183).

### Attachment extraction and OCR (v0.3.1)
- **Text layer first, OCR second.** `DocumentExtractionService` reads the embedded text layer (`PDFDocument.page.string`, or UTF-8 text); when that yields fewer than `DocumentTextRecognizer.minimumTextLayerCharacters` (16), it falls back to on-device Vision OCR (`VNRecognizeTextRequest`, `.accurate`) on the rendered page. Scanned or photographed PDFs have **no text layer**, so without this the attachment was silently empty and the model answered as if nothing were attached. OCR is local; nothing is uploaded.
- **Long documents are excerpted by relevance, not truncated by position.** `DocumentExcerptBuilder` chunks the text and keeps the chunks that score best against the user's prompt (BM25 via `DocumentSearchService`), preserving reading order and marking the result `[Excerpted the N most relevant part(s) …]`. Plain head truncation used to drop the answer whenever it sat past the budget — which is only ~1,600 characters on LiteRT's 2048-token window.
- **Unreadable documents are surfaced.** `DocumentExtractionService.hasNoReadableText` drives a system notice in `ChatTurnEngine` ("Couldn't read any text from …") so a failed extraction is visible instead of looking like a model failure.
- `attachment(from:)` and `libraryPages(from:)` are **async** (OCR is asynchronous); update callers accordingly.

### Document library and search (v0.3.1)
Imported files live under `Application Support/DocumentsLibrary/` (excluded from backup): `index.json` ([`LibraryDocument`]), `<id>.chunks.json` ([`DocumentChunk`] with optional `pageNumber`/`lineRange`), and `<id>.vectors.bin` (header `dimension:UInt32`, `count:UInt32`, kind tag, then little-endian `Float32` rows). `DocumentLibraryStore` (`@MainActor @Observable`) owns the index and a cached `DocumentSearchIndex` snapshot; `importDocument(from:)` drives the `DocumentIndexer` actor (extract → chunk → embed) and marks the document `.indexing` → `.ready`/`.failed`. Deleting a document mid-index discards the result.
- **Chunking** — `DocumentChunker` targets 800 characters with 150 characters of overlap, splitting on paragraph then `NLTokenizer` sentence then a hard cut. PDFs keep `pageNumber`; text keeps `lineRange`. The overlap shrinks when needed so no chunk exceeds the target.
- **Embeddings** — `DocumentEmbedder` prefers `NLContextualEmbedding` (mean-pooled, only when `hasAvailableAssets`), then `NLEmbedding.sentenceEmbedding`, else `.none` (keyword-only). Rows are **positionally aligned with the chunks**: a chunk that fails to embed becomes an inert zero vector rather than being dropped, because a shortened array used to make `DocumentIndexer` discard the vectors for the *whole* document (`vectors.count != chunks.count`). A query is embedded with the **document's** detected language, not the query's — using the query's language put the two vectors in different embedding spaces whenever the user asked in a different language from the document.
- **Search** — `DocumentSearchService.search(query:index:limit:)` scores `max(normalizedBM25, 0.7 × cosine + 0.3 × normalizedBM25)` when vectors exist, and normalized BM25 alone for `.none`; top 5 by default. The `max` matters: the vector signal must never *demote* a chunk BM25 matched strongly, since query and document vectors are not always comparable. `renderHits` labels passages `[fileName p.12]` and bounds total text by `InferenceBudget.documentContextBudget(for:)` — including truncating the first block, which used to be appended in full even when it alone exceeded the budget.
- **Models** — `SearchDocumentsTool` (`search_documents`) is registered only when `AppSettings.documentSearchEnabled` (default on) **and** the index is non-empty; each hit becomes a citation-style source. `ToolRegistry.dispatch` re-checks that gate, so a model cannot invoke a tool that was not offered this turn. For models **without** the tool loop the only route is the upfront path in `UpfrontToolDetector`, which fires on a document phrase *or* on a content question ("What does the contract say about termination?") — the old 16-literal-phrase gate meant 24 of the 46 catalog models could never reach the library at all. A turn that is purely social is skipped. Indexing is 100% on-device and no user content is sent anywhere.
- **Library failures are surfaced** — a document stuck in `.failed`, or a library whose index cannot be loaded, now produces a chat notice; `DocumentLibraryStore.chunks(for:)` logs decode failures instead of silently returning `[]` (which made one corrupt file look like an empty library).

### Model suggestions (v0.3.1)
`ModelSuggestionAdvisor.suggestion(prompt:hasImage:hasDocuments:current:installed:profiles:tier:)` is a pure function that never switches models. Rules in priority order: (1) an image is attached and the current model's profile `vision != .imageAndText`; (2) the current model's verdict is red (a **green** candidate is required here); (3) a document/tool intent is detected and the current model has no verified tool calling. "Best" candidate = green verdict, then recommended for the tier, then smallest `parsedDiskSizeGBForEstimator`; candidates must be `.installed` and allowed on `DeviceTier.current()`. `ChatView` renders it as a dismissible composer banner, suppressed for the rest of the session once dismissed.

### Inference layer (`Services/Inference/`)
Four concrete backends behind the `InferenceService` protocol, selected by `ModelCatalogItem.RuntimeType` (`.gguf`, `.mlx`, `.liteRTLM`, `.foundationModels`):

- **`LocalLlamaInferenceService`** — GGUF models via llama.cpp C API. Contains the `PromptRenderer` enum (token budget calculation, HTML stripping, chat-turn assembly). `PromptRenderer` is `internal` for testability. Does **not** support image input — throws if `imageData != nil`.
- **`MLXInferenceService`** — MLX models via the `mlx-swift-lm` package (MLXLLM, MLXVLM). Falls back to a plain prompt string for models without a chat template. Only loads the SigLIP vision tower when `imageData != nil && supportsVision` to prevent OOM on 8 GB devices.
- **`LiteRTInferenceService`** — Gemma 4 E2B/E4B via the local `Vendor/LiteRT-LM` Swift package. Supports vision for the E2B variant; image streams are bounded by timeouts and cancellation (`ef11cd5`, `92e8977`).
- **`AppleFoundationModelService`** — Apple Intelligence Foundation Models (on-device system runtime, no downloaded weights). Gated by `AppleFoundationModelService.availabilityMessage`; throws when unavailable. The catalog's "Apple Intelligence" entry (`runtimeType: .foundationModels`) is the only path that uses it.

`ChatTurnEngine` holds one instance per backend (in its `LiveServices` holder) and routes via its `serviceForModel` dependency, which `switch`es on `runtimeType`. Before each call it calls `RuntimeMemoryCoordinator.prepareForRuntime(...)` to free the previous runtime's memory.

`AssistantResponseSanitizer.clean()` (in `InferenceService.swift`) strips model-specific tokens (`<|im_end|>`, `[INST]`, etc.) from streamed output before display. `TokenLeakScrubber` additionally scrubs per-model `knownLeakTokens` declared in the runtime profile. `ResponsibleAIGuard` is a pre-flight safety filter on outgoing prompts.

**Context and token budgets** — `InferenceBudget` is the single source of truth:
- `safeContextWindow(for:)` clamps per runtime: GGUF uses `DeviceCapabilityService.contextSize()`, MLX/FoundationModels use `DeviceTier.safeContextTokens`, LiteRT caps at 2048.
- `maxGeneratedTokens(for:searchContext:)` = 1024 chat / 2048 with search, capped to `contextWindow - 256`.
- `mlxHistoryBudget(...)` reserves prompt space and returns the history token budget.
Do not hardcode prompt/context limits — always go through `InferenceBudget`.

**`DeviceCapabilityService`** reads `hw.machine` via `sysctlbyname` for GGUF `n_ctx` selection and flash-attention gating (A14 = disabled). The cross-runtime tier system is `DeviceTier` (see below).

### Stream processing (`Services/Inference/StreamProcessor.swift`)
`StreamProcessor` is an `actor` that sits between the raw `AsyncStream<String>` from inference backends and the UI. It parses the token stream into typed `StreamEvent` values: `.textDelta`, `.thinkingDelta`, `.thinkingDone`, `.toolCall`, and `.done(GenerationStats)`. Both `LocalLlamaInferenceService` and `MLXInferenceService` wrap their raw streams through `StreamProcessor` before returning.

Key behaviors:
- **Think block extraction**: Detects `<think>`, `<thinking>`, `<reasoning>` tags (case-insensitive) and routes content to `.thinkingDelta`/`.thinkingDone` events. Auto-closes unclosed think blocks at stream end.
- **Tool call parsing**: Detects `<tool_call>…</tool_call>` blocks, parses the JSON for a `name` field, and yields `.toolCall`. Only one tool call per stream is honored (`toolCallFired` guard) — subsequent `<tool_call>` blocks are flushed as plain text. Tool-call termination does NOT emit `.done` — `ChatView` re-invokes inference, so there is no terminal stats payload on that path.
- **Generation stats (0.3.0)**: `.done` carries a `GenerationStats` payload (time-to-first-token, total duration, token count). `StreamProcessor` accumulates wall-clock timing and a delta count via `StatsAccumulator` for every backend. Exact token counts are injected by an `exactTokenCountProvider` closure supplied at init — GGUF via `LocalLlamaRuntime.lastGeneratedTokenCount()` (`generatedTokenCount`), MLX via the previously-discarded `.info(GenerateCompletionInfo)` case. Aborted streams (watchdog timeout, repetition guard) skip the exact-count provider and rely on the delta-count fallback. **All four runtimes now route through `StreamProcessor`, including `AppleFoundationModelService`** — it used to hand its text straight to the UI, which is why `<tool_call>` blocks were never parsed for Apple Intelligence.
- **Unterminated tool call**: at stream end an unclosed `<tool_call>` buffer is *parsed* — if its arguments are well-formed it emits `.toolCall` rather than being flushed as prose (a truncated call used to become a wrong answer). Garbage still degrades to text. This also covers a call opened inside a think block, which the old `else if` dropped entirely.
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
Static array of `ModelCatalogItem` structs — currently 46 entries spanning Apple Intelligence, Granite, Gemma (2/4), Llama, Phi, DeepSeek, Mistral, SmolLM/SmolVLM, Qwen (3 / 3.5 / 3.5 VL), and LFM 2.5 families across GGUF, MLX, LiteRT-LM, and FoundationModels runtimes. Each entry carries both *advertised* and *runtime* fields:

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
Tool-calling models (catalog `supportsToolCalling` **and** a `verifiedToolCalling` profile) drive a multi-step agentic loop. The model receives the user message with a `# Tools` prompt section (rendered by `ToolRegistry.renderPromptSection`) and may emit a `<tool_call>` block. `StreamProcessor` yields `.toolCall(name, argsJSON)`; `ChatTurnEngine.runToolLoop` then dispatches via `ToolRegistry`, appends the tool's result text to the system prompt, and re-invokes inference — looping up to `ToolRegistry.maxIterations` (3) times so the model can chain tool calls. Non-tool-calling models fall back to upfront search (auto-detect or user toggle). `web_search` keeps its structured `searchContext` render path unchanged; all other tools render as plain `# Tool result:` text appended to the system prompt. **No `InferenceService` signature change** — tool results never touch the protocol.

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
- `EdgeMindAiApp.swift` (@main): creates the shared `AppStateStore`, `ChatTurnEngine`, `MemoryStore`, and `DocumentLibraryStore`, registers them in `AppServices.shared` (so Shortcuts can reach the engine), and injects `AppStateStore`, `AuthStateStore`, `ChatTurnEngine`, `MemoryStore`, `DocumentLibraryStore`, and `DeepLinkCoordinator` into the environment, gates `RootView` behind auth via `LaunchRootView`, and applies `.preferredColorScheme(store.settings.appearanceMode.preferredColorScheme)` at the window level. The engine is built from `ChatTurnEngine.Dependencies.live()`.
- `ChatTurnEngine` (`Services/Chat/`) owns the chat turn pipeline: the four `InferenceService` instances (one per runtime, kept alive in a `LiveServices` holder), `isGenerating`, the active generation task, the interruption reason, `prewarmDefaultModel()`, memory-warning handling, and the 90-second idle runtime release. `send(_ request: TurnRequest)` runs preflight, context/tools, stream, tool loop, fallbacks, then finish; `stop()` and `handleMemoryWarning()` interrupt a turn. All writes go through a `TurnOutput`; `StoreTurnOutput` maps each call 1:1 onto `AppStateStore` mutations and enforces the **single-finish invariant** (exactly one `finish` per turn on every path). `ChatTurnEngine+Tools.swift` holds the tool loop and tool helpers; `Dependencies.live()` wires the real runtimes and `RuntimeMemoryCoordinator`. Unit tests drive it with `ScriptedInferenceService`.
- `ChatView.swift` is UI only: it owns prompt/attachments/focus/pickers/scroll state, calls `engine.send(...)`/`engine.stop()`, and renders `MessageBubbleView` from `store`. It does not hold inference services or run the streaming loop; its composer reads `engine.isGenerating` for the Stop affordance.
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
7. **Verify documentation freshness**: Whenever `MockCatalogData.swift`, `project.yml`, or runtime profiles change, developers and agents must update all documentation with accurate counts/versions and run the freshness verification script before committing:
   ```bash
   python3 scripts/verify_docs_freshness.py
   xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max' -only-testing EdgeMindAiTests/DocumentationFreshnessTests
   ```

## llama.cpp xcframework

The pre-built xcframework at `Vendor/build-apple/llama.xcframework` is vendored in-repo and linked directly via `project.yml` (`embed: true`, `codeSign: true`). Do not replace or update the xcframework without rebuilding all test targets. The LiteRT runtime is pulled from the local `Vendor/LiteRT-LM` Swift package (declared under `packages:` in `project.yml`); MLX comes from `mlx-swift-lm`, and HF/tokenizer support from `swift-huggingface` + `swift-transformers`.

## Gotchas

- **Every assembled prompt must fit the model's context window (`InferenceBudget.fitPrompt`)**: LiteRT-LM hard-caps at **2048 tokens** and fails the whole request above it with `INVALID_ARGUMENT: Input token ids are too long: N >= 2048` — it does not silently truncate. Inlined attachment text is bounded by `InferenceBudget.documentContextBudget(for:)` in `ChatTurnEngine`, GGUF clamps inside `PromptRenderer`, and `LiteRTInferenceService.budgetedTurn` clamps the total (current turn first, then oldest history). Never inline a document, tool result, or search snippet without a budget — a flat 20,000-character PDF is ~5,000 tokens. `PromptBudgetTests` sweeps a worst-case prompt across **all 46 catalog models**; keep it green when adding prompt sections.

- **Gemma 4 runs on LiteRT-LM, not MLX**: The Gemma 4 E2B/E4B catalog entries use `runtimeType: .liteRTLM` and load via `LiteRTInferenceService` from `Vendor/LiteRT-LM`. The E2B variant supports vision; the **E4B vision path failed the on-device audit** (`image-runtime-failed-xnnpack-allocation`), so its catalog entry has `supportsVision: false` and a `.yellow(...)` `auditVerdict` — it is text+document only despite the upstream E4B being a VLM.
- **Gemma 4 thinking token format**: Gemma 4 models use `<|channel>thought\n...<channel|>` tokens for their thinking/reasoning block, NOT `<think>` tags. `StreamProcessor` CAN parse this (`ThinkFormat.gemmaChannel`), but only when the model's RuntimeProfile sets `verifiedThinking: "gemmaChannel"` (that's what populates `activeThinkFormats`). No profile sets it yet, so Gemma 4 thinking still renders inline and `isThinkingModel: false` remains correct in the catalog — flip profile first (after a device probe), then the catalog flag.
- **Gemma 4 native tool-call payload is NOT JSON**: Gemma 4 emits `<|tool_call>call:NAME{key:<|"|>value<|"|>, n:30}<tool_call|>` (typed arguments, per Google's Gemma 4 prompt-formatting docs). `GemmaToolCallPayload` (in `StreamProcessor.swift`) converts this to the app's `(name, argsJSON)` shape; `StreamProcessor.parseToolCall` tries it before the JSON path. `GemmaToolCallPayloadTests` locks one stream-level fixture per declared `ToolCallFormat` — keep that invariant when adding formats.
- **Qwen 3.5 models are VLMs**: All Qwen 3.5 sizes (0.8B–9B) have a vision encoder. They accept `image_url` inputs and report VideoMME benchmark scores. In the MLX app, image input works via `VLMModelFactory`. Context is 256K tokens (262,144), not 32K. The MLX repo IDs are `mlx-community/Qwen3.5-{size}-4bit` (no "VL" in the name) — model-ID string checks must match `qwen3.5-4b`, not `qwen3-vl-4b`.
- **Qwen 3.5 VL 4B image path**: its first on-device image audit was OOM-killed (`image-prefill-memory-killed-on-device-text-only`) because the old model-ID check never matched, so it ran the generic 384px/unbounded-KV path. It now gets the constrained-vision treatment (192px, `kvBits: 4`, `prefillStepSize: 16`, wired-memory ticket — see `isConstrainedVisionModel` in `MLXInferenceService`). Catalog stays `supportsVision: false` until an on-device re-audit passes; then flip catalog `supportsVision` + `inputModes` + profile `verifiedVision` together. Gemma 4 E4B (LiteRT) vision remains a vendor xnnpack limitation — retry only after the next `Vendor/LiteRT-LM` update.
- **Gemma 4 context**: Gemma 4 E2B and E4B support 128K tokens in context (all catalog entries now say 128K; `CatalogConsistencyTests` enforces that the same model advertises the same context window across runtimes). The LiteRT-LM runtime exposes the full context via the model weights, though `InferenceBudget` still clamps LiteRT to 2048 at runtime.
- **LFM2.5 VL tool calling is text-only**: Per the official docs, `LFM2.5-VL-1.6B` supports tool calling for text-only inputs. Tool calls will not fire when the message content includes an image.
- **LFM2.5-1.2B-Thinking is a separate model**: The `LFM2.5-1.2B-Instruct` model does NOT have a thinking mode. Thinking is available only in `LFM2.5-1.2B-Thinking` (a distinct model variant). The catalog carries the `Thinking` variant (with `isThinkingModel: true`); do not set `isThinkingModel: true` on the Instruct variant.
- **`PromptRenderer` dynamic budget**: `maxPromptTokens = max(256, nCtx - maxGeneratedTokens - 64)`. On a 2048 n_ctx device in search mode, this floors at 256 tokens. Do not hardcode prompt limits.
- **Context reuse (0.3.0)**: `maxGeneratedTokens` is now a **per-call** parameter, not a context-creation/cache key. `LocalLlamaRuntime.ensureContext(for:)` keys only on `modelPath` — toggling search (2048) vs chat (1024) mode no longer triggers a model reload. The cap is passed into `LocalLlamaContext.generate`/`generateStream(maxGeneratedTokens:)` per call and read by `generationStep()`'s stop guard. Do not reintroduce `maxGeneratedTokens` into the cache key.
- **MLX/LiteRT on simulator**: MLX calls are guarded by `#if canImport(MLXLLM) && !targetEnvironment(simulator)`; LiteRT-LM likewise does not run in the simulator. Only GGUF models work in the simulator. The simulator also excludes `x86_64`, so Apple Silicon hosts are required. **The simulator compiles the `#else` branch of those guards**, so MLX/LiteRT code is not even type-checked by a simulator build or by the unit suite — a green test run does not mean those files compile. Always run a device build (`-destination 'id=<device-udid>'`) after touching `LiteRTInferenceService` or `MLXInferenceService`.
- **Sign in with Apple**: `com.apple.developer.applesignin` is currently commented out in `EdgeMindAi.entitlements`. The team is on a **paid** Apple Developer Program, so it can be re-enabled — it was left disabled because the v0.1.0 submission does not require cloud auth, and `APP_STORE_REVIEW_NOTES.md` tells reviewers the app needs no remote account. Re-enable it only if you intend to ship SiwA in a future version.
- **`project.yml` is the source of truth**: Running `xcodegen generate` overwrites `.xcodeproj`. Stage `project.yml` changes before generating. **Committing a `project.yml` change without regenerating ships the old value** — the version/build number only reaches the build through the generated `project.pbxproj`, which is tracked, so commit that too.
- **Finder duplicates break `xcodegen generate`**: XcodeGen globs the source tree, so a stray `Foo 2.swift` (or `Info 2.plist`, `EdgeMindAi 3.xcodeproj`) gets pulled into the build and fails with *duplicate declarations* — even though it is untracked and absent from the current `.xcodeproj`. On 2026-09-16 that was 42 files plus six stray projects, and it re-appeared repeatedly across sessions. If generation or a fresh build fails this way: `find . -path ./.git -prune -o -name "* 2.*" -print` and delete them.
- **Two independent test-count gates**: `scripts/verify_docs_freshness.py` and `EdgeMindAiTests/DocumentationFreshnessTests` each count `func test…()` methods under `EdgeMindAiTests/`. Adding tests means updating the `| Unit tests |` row in `README.md` and re-running **both** — they can disagree briefly if a test file is malformed.
- **Design system supports light + dark**: `AppTheme` defines `light` and `dark` variants for every color and adapts via `UITraitCollection.userInterfaceStyle`. `AppSettings.appearanceMode` (`.system` default / `.dark` / `.light`) is applied once at the window root via `.preferredColorScheme(...)`. Do not add per-view `colorScheme` conditionals — extend `AppTheme` if a new adaptive color is needed.
- **Citations are not a chat role**: `ChatMessage.Role` is `system`/`user`/`assistant` only — the legacy `.search` role has been removed. Search citations live on `ChatMessage.citations: [SearchCitation]` and should render as a "Sources" footer on the assistant bubble. Do not reintroduce a `.search` role.
- **App Intents handoff**: `LocalAIAppIntents.swift` defines `OpenLocalAIDestinationIntent`, `AskDefaultLocalModelIntent`, and `StartLocalVoiceChatIntent`. They stash a `LocalAIIntentDestination` (`.chat`/`.models`/`.voice`) + optional prompt/voice flag via `LocalAIIntentBus.save(...)`, which the UI consumes once on launch via `consume*()`. When wiring new shortcuts/Siri intents, route through the bus rather than touching `AppStateStore` directly from the intent.
- **Image attachments are downsampled before inference**: `ChatComposerView` bounds JPEG encoding to prevent OOM. Do not pass raw `UIImage` to the inference service.
- **MLX GPU cache**: `MLXRuntime` unloads the previous model and calls `GPU.clearCache()` before loading a new one. Vision models get a larger cache limit (768 MB vs 512 MB) to accommodate the SigLIP tower. `RuntimeMemoryCoordinator.prepareForRuntime(...)` is the cross-runtime entry point `ChatTurnEngine` calls before every inference call — it unloads the previous runtime so GGUF/MLX/LiteRT/FoundationModels do not co-occupy memory.
- **Tool loop is bounded (`ToolRegistry.maxIterations = 3`)**: `ChatTurnEngine.runToolLoop` re-invokes inference after each tool result; a model that keeps emitting `<tool_call>` is capped at 3 iterations, after which a "tool-call limit" system message is shown. The loop lives in `ChatTurnEngine+Tools.swift`, NOT in `StreamProcessor` — the parser still terminates the *current* stream on the first tool call (correct: the model is signaling it wants a tool).
- **`CalculateTool` thousands-separator commas vs argument commas**: `MathEvaluator.stripNumericCommas` strips a comma ONLY when it sits between two digits (`1,000` → `1000`), so function-argument commas (`max(3, 9)`) are preserved. Do not revert to a blanket `replacingOccurrences(of: ",", with: "")` — it breaks multi-argument functions.
- **`web_search` keeps its structured render path**: even though it's now a `Tool`, `WebSearchTool` returns `ToolResult.searchContext`, which `ChatTurnEngine` passes through `generateStream(searchContext:)` so the existing `PromptRenderer`/`MLXInferenceService.buildSystemPrompt` snippet rendering is unchanged. Do not migrate `web_search` to the plain-text `# Tool result:` path without unifying the two renderers.
- **Composer body type-checker fragility**: `ChatComposerView.body` is large enough that adding modifiers can trip Swift's "unable to type-check in reasonable time" error. Sheets/alerts/pickers live in a `private View` extension (`composerPresentationModifiers`) and the trailing button group is extracted to `trailingAction`. Add new composer modifiers to the extension, not inline in `body`.
