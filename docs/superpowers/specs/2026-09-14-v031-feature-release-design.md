# Edge Mind Ai — Feature Release Design (0.3.1 / 0.3.2)

**Status:** Approved in design review, September 14, 2026
**Scope:** Seven user-facing features, plus one enabling refactor (step 0).
**Constraints that apply throughout** (see `AGENTS.md` → Release & App Store submission):
- All inference and data stay on the device. No telemetry, analytics, or cloud sync.
- No remote account. Guest users must always reach chat.
- Any new networking is opt-in and visible to the user. This release adds none.
- `InferenceBudget` is the only source of context and token limits.
- MLX and LiteRT keep their simulator compile guards.

## Release targeting

- 0.3.1 (build 7) contains the iOS 26.6.1 launch-hang fix and is `WAITING_FOR_REVIEW`. It stays in review while this work is built.
- When all features pass the gates below:
  - If 0.3.1 is still in review, pull it, bump the build number, and resubmit as 0.3.1.
  - If Apple has already approved 0.3.1, ship this work as 0.3.2.
- Use the `/app-store-release` skill for either path.

## Build order

Each step is its own commit and must pass every gate in Testing before the next step starts.

| Step | Work |
|---|---|
| 0 | Extract `ChatTurnEngine`. Add the App Group and URL scheme. No user-visible change. |
| 1 | Regenerate (versioned answers) and edit-and-resend |
| 2 | Export chat as Markdown and PDF |
| 3 | Model suggestions per task |
| 4 | Personal memory |
| 5 | Document library and search |
| 6 | Share Extension, and Shortcuts that return answers |
| 7 | Home-screen and lock-screen widgets |

---

## 1. Data model and storage

### Answer versions (regenerate)

`ChatMessage` gains two fields:
- `versions: [AnswerVersion]`, defaulting to `[]`.
- `selectedVersion: Int`, defaulting to `0`.

```swift
struct AnswerVersion: Identifiable, Hashable, Codable {
    let id: UUID
    var text: String
    var thinkingContent: String?
    var thinkingDurationSeconds: Int?
    var generationDurationSeconds: Double?
    var stats: GenerationStats?
    var toolActivities: [ChatToolActivity]
    var citations: [SearchCitation]
    var modelName: String
    let createdAt: Date
}
```

Rules:
- **Mirroring.** A message's top-level fields (`text`, `thinkingContent`, `stats`, `toolActivities`, `citations`, durations) always mirror the selected version. All existing readers (bubbles, history search, export, the prompt history sent to models) keep reading the top-level fields and need no change.
- **Legacy data.** An empty `versions` array means the message has exactly one implicit version. Old persisted data decodes with `decodeIfPresent` defaults.
- **First regenerate.** The current top-level content is snapshotted as version 0, and the new answer becomes version 1.
- **Cap.** At most 5 versions per message. A 6th regenerate removes the oldest non-selected version.
- **Model history.** Only the selected version is sent to models as conversation history.
- **Trimming.** Persistence and in-memory text caps (`AppStateStore` limits) apply to every version. Sanitizers copy and mutate; they must never rebuild a message field by field (see commit `8140174`).

New `AppStateStore` methods:
- `beginRegeneration(messageID:in:modelName:) -> UUID`: snapshots version 0 if needed, appends an empty version, selects it, and returns the version ID.
- `selectVersion(_ index: Int, of messageID:in:)`: mirrors that version into the top-level fields and persists.
- The existing `update*` mutations write to the selected version *and* the top-level mirror whenever `versions` is non-empty.

### Edit and resend

`AppStateStore.removeMessagesForEdit(from messageID: UUID, in sessionID: UUID) -> ChatMessage?`:
- Requires `role == .user`.
- Removes that user message and every later message, updates `updatedAt`, persists, and returns the removed user message so its attachments can be reused.
- Returns `nil` (and changes nothing) for a non-user message.

### Personal memory

```swift
struct MemoryItem: Identifiable, Hashable, Codable {
    let id: UUID
    var text: String       // ≤ 200 characters
    var isEnabled: Bool
    let createdAt: Date
}
```

- `MemoryStore` is `@MainActor @Observable`, persisted under its own UserDefaults key `persistedMemoryItems`, with at most 50 items.
- `InferenceBudget.memoryTokenBudget(for: InstalledModel) -> Int` sets the prompt allowance:
  - About 150 tokens when the safe context is 2,048 tokens or less.
  - About 300 tokens when it is 4,096.
  - About 500 tokens otherwise.
- Items are rendered newest-first into a `# About the user` system-prompt section and trimmed to fit the budget.

### Document library

Stored under `Application Support/DocumentsLibrary/`, excluded from backup:

| File | Contents |
|---|---|
| `index.json` | `[LibraryDocument]`: `id`, `fileName`, `kind`, `importedAt`, `isEnabled`, `chunkCount`, `embeddingKind`, `indexState` (`indexing` / `ready` / `failed(message)`) |
| `<id>.chunks.json` | `[DocumentChunk]`: `index`, `text`, `pageNumber?`, `lineRange?` |
| `<id>.vectors.bin` | Header (`dimension: UInt32`, `count: UInt32`, `embeddingKind` tag), then little-endian `Float32` rows |

- Library imports cap extracted text at 2 MB per document. The existing 20,000-character cap still applies to prompt-inlined chat attachments.

### Share inbox (App Group)

- App Group ID: `group.com.vinothrajalingam.EdgeMindAi`.
- Container path: `Inbox/<uuid>/payload.json` plus an optional copied file.

```swift
struct SharePayload: Codable {
    let id: UUID
    let action: ShareAction      // summarize, explain, ask
    let question: String?        // for .ask
    let text: String?            // shared text or URL string
    let fileName: String?        // copied file inside the item folder
    let createdAt: Date
}
```

- The app drains the inbox on launch and on `scenePhase == .active`, deleting each item after import. Items older than 24 hours are discarded.
- Chat sessions, settings, and installed models are **not** moved into the App Group.

### Settings

`AppSettings` gains two flags, both decoded with defaults:
- `memoryEnabled` (default `true`)
- `documentSearchEnabled` (default `true`)

---

## 2. `ChatTurnEngine`

### Ownership

- `@MainActor @Observable final class ChatTurnEngine`, created in `EdgeMindAiApp` and injected into the environment.
- **Owns (moved out of `ChatView`):**
  - the four `InferenceService` instances
  - `isGenerating`, `activeGenerationID`, the generation task
  - `generationInterruptionReason`
  - `idleRuntimeReleaseTask`
  - memory-warning handling
  - `prewarmSelectedModel`
- **`ChatView` keeps** only UI state: prompt text, attachments, focus, pickers, and scroll.

### API

```swift
struct TurnRequest {
    enum Target {
        case newMessage
        case regenerate(assistantMessageID: UUID, model: InstalledModel?)
    }
    let sessionID: UUID
    let prompt: String
    let attachments: [ChatAttachment]
    let imageData: Data?
    let liveSearchEnabled: Bool
    let target: Target
}

func send(_ request: TurnRequest)
func stop()
func handleMemoryWarning()
func answerHeadless(prompt: String) async throws -> String   // throws HeadlessAnswerError.needsApp
```

Behavior by target:
- **`.newMessage`:** appends the user message, then an assistant placeholder. This is today's behavior.
- **`.regenerate`:** history is the session messages *before* the assistant message. The prompt is the preceding user message's text plus document context, and the image is that message's image. Output goes to a new version created by `beginRegeneration`. When a `model` is given, it overrides the default for this turn only.
- **Edit:** the view calls `store.removeMessagesForEdit(from:in:)`, then `send(.newMessage)` with the edited text and the returned message's attachments. The engine appends the edited user message as usual, so no message is duplicated.

### Output

```swift
@MainActor protocol TurnOutput {
    func update(text: String, persist: Bool)
    func update(thinking: String, duration: Int?, persist: Bool)
    func setToolActivities(_ activities: [ChatToolActivity], persist: Bool)
    func setCitations(_ citations: [SearchCitation])
    func appendNotice(_ text: String)                 // system message
    func finish(text: String, stats: GenerationStats?, duration: Double?)
}
```

- `StoreTurnOutput` writes to the base message or the selected version.
- `CollectingTurnOutput` keeps the final text for headless answers, and also saves the turn as a new chat titled from the prompt.
- **Invariants:**
  - Exactly one `finish` call per turn, on every path: normal, stop, error, tool-loop abort, and fallback retry.
  - The Stop notice is appended inside `finish` whenever the task was cancelled.
  - Voice auto-play is triggered from `finish` only when the turn was not cancelled.

### Pipeline stages

1. **Preflight:**
   - ready model (override or default)
   - `memoryGuardMessage`
   - `ResponsibleAIGuard`
   - image capability
   - the `.newMessage` user append
2. **Context:**
   - memory section, when enabled and not an OpenELM lane
   - tool availability: web search, local tools, `search_chats`, `read_document`, and `search_documents` (step 5)
   - upfront search and upfront local tools for non-tool models, with the same rules as today
3. **Stream:** one `consume(stream:into:)` handles text flushing (80 ms), thinking, `.toolCall`, and `.done`. The tool loop (`ToolRegistry.maxIterations`) calls the same consumer.
4. **Fallbacks:** post-stream missed-tool-call search, search-grounding retry, and empty-output retry. The conditions are unchanged from `ChatView` at commit `983b8cd`.
5. **`finish`**, then the idle runtime release is scheduled after 90 seconds.

### Headless answers (Shortcuts)

- Allowed only when the default model is Apple Intelligence, or is a ready model with `diskSizeGB ≤ 2` and `AvailableMemoryGuard` passes.
- Otherwise throws `.needsApp`.
- A 120-second timeout returns the partial text, or throws if nothing was produced.

### Model suggestions (feature 3)

`ModelSuggestionAdvisor.suggestion(prompt:hasImage:hasDocuments:current:installed:profiles:tier:) -> ModelSuggestion?` is a pure function that never switches models. Rules, in priority order:
1. An image is attached and the current model's profile `vision != .imageAndText`. Suggest the best installed model with verified vision allowed on this tier.
2. The current model's `auditVerdict` is red. Suggest the best green installed model.
3. A document search or tool intent is detected, and the current model has no verified tool calling. Suggest a tool-verified model (suggestion only; the upfront path still works).

"Best" means: green verdict first, then recommended for this tier, then smallest disk size. The composer shows it as a dismissible banner, suppressed for the rest of the session once dismissed.

---

## 3. Document library and search (feature 5)

### Import

- **Entry points:** Settings → Documents, the composer `+` menu, and Share Extension imports.
- `actor DocumentIndexer` handles extraction, chunking, and embedding. Progress is published per document, and indexing can be cancelled by deleting the document.

### Chunking

- Target length 800 characters, with 150 characters of overlap.
- Split preference: paragraph (`\n\n`), then sentence (via `NLTokenizer(unit: .sentence)`), then a hard cut.
- PDF chunks keep their page number. Text chunks keep their line range.

### Embeddings

1. **Preferred:** `NLContextualEmbedding(language:)` when `hasAvailableAssets`, with vectors mean-pooled. Asset requests are left to the system; no user content is sent.
2. **Fallback:** `NLEmbedding.sentenceEmbedding(for: language)`.
3. **Otherwise:** `embeddingKind = .none`, and the document is searchable by keyword only.

- The document language comes from `NLLanguageRecognizer`. Queries are embedded with the same kind as the target document.
- If a better embedding kind becomes available later, ready documents are re-indexed in the background.

### Search

- `DocumentSearchService.search(query:limit:) async -> [DocumentHit]` covers enabled, ready documents.
- **Score:** `0.7 × cosine + 0.3 × normalized BM25`. Keyword-only documents use BM25 alone.
- **Memory:** vectors are memory-mapped (`Data(contentsOf:options:.alwaysMapped)`), so the in-memory size does not grow with the library.
- **Results:** top 5 hits by default. Each hit carries `documentID`, `fileName`, `pageNumber`, `text`, and `score`.

### How models use it

- **`SearchDocumentsTool` (`search_documents`, arg `query`):** registered in `ToolRegistry.availableTools` only when `documentSearchEnabled` is on and at least one ready, enabled document exists. It returns labeled chunks (`[fileName p.12] …`), and each hit becomes a citation-style source on the answer.
- **Non-tool models:** `UpfrontToolDetector` runs the search when the prompt references documents ("my document", "the PDF", "according to", a library file name) or when the turn came from a share import.
- **Budget:** total injected chunk text is bounded by `InferenceBudget.documentContextBudget(for:)`, which grows with the context window.

### Long chat attachments

- A per-chat attachment whose extracted text exceeds 20,000 characters is indexed into a temporary, session-scoped index instead of being truncated.
- `read_document` then searches that index. The temporary index is deleted with the session.

---

## 4. App extensions, Shortcuts, export, memory, and chat UI

### Share Extension (`EdgeMindShare`)

- A new `app-extension` target in `project.yml` with the App Group entitlement and a SwiftUI sheet.
- **Accepted input:** `public.plain-text`, `public.url`, `com.adobe.pdf`, `public.comma-separated-values-text`, markdown, and `public.image`.
- **Sheet actions:** Summarize / Explain / Ask (the question field is required for Ask).
- **On confirm:** copies the file (≤ 50 MB), writes `payload.json`, then opens `edgemindai://share/<id>`.
- **No inference or indexing** runs in the extension (iOS limits extensions to roughly 120 MB). URLs are passed as text; the app never fetches them.
- **In the app:**
  - Documents are imported to the library.
  - Images and text are attached to a new chat.
  - Summarize and Explain auto-send. Ask pre-fills the prompt and sends.

### URL scheme

- `edgemindai://` is registered in the app target and handled in `EdgeMindAiApp.onOpenURL` by a `DeepLinkRouter`. Supported routes:
  - `ask?mode=text|voice|camera`
  - `share/<id>`
  - `settings/memory`
  - `settings/documents`
- Routing reuses `LocalAIIntentHandoffStore` and the `SelectedTabKey` navigation.

### Widget (`EdgeMindWidget`)

- A WidgetKit extension with a static timeline and no shared data.
- **Families:** `systemSmall` (Ask), `systemMedium` (Ask / Voice / Camera), and `accessoryCircular` (Ask).
- Each button is a `Link` to `edgemindai://ask?mode=…`. No chat content is ever shown.

### Shortcuts

- `AskDefaultLocalModelIntent` sets `openAppWhenRun = false` and conforms to `ReturnsValue<String> & ProvidesDialog`.
- It calls `ChatTurnEngine.answerHeadless`. On `.needsApp` it returns `.result(opensIntent: OpenLocalAIDestinationIntent(prompt))`.
- `OpenLocalAIDestinationIntent` and `StartLocalVoiceChatIntent` are unchanged.
- The engine is reached through a shared app-level instance, `AppServices.shared`, which is created by `EdgeMindAiApp` and is also reachable when the intent runs in the background.

### Export (feature 2)

- `ChatExporter.markdown(session:includeThinking:) -> String`
- `ChatExporter.pdf(session:includeThinking:) async -> URL`, rendered with `UIGraphicsPDFRenderer` on a Letter page:
  - text laid out with `NSAttributedString`
  - images scaled to page width
  - a sources list per answer
- Files are written to a temporary directory and deleted on the next export.
- The UI lives in the chat header menu: "Share chat…", then a format choice and an "Include thinking" toggle, then a `ShareLink`.

### Memory UI (feature 4)

- **Settings → Memory:** list, add, edit, enable toggle, swipe to delete, "Clear all" (with confirmation), and a `memoryEnabled` master switch.
- **In chat:** the phrases "remember that …", "remember I …", and "don't forget …" are detected in the user prompt before sending. A confirmation card offers **Save** or **Don't save**. The turn proceeds either way.
- **Answers:** an answer that used memories shows a "Using N memories" chip, which links to `edgemindai://settings/memory`.

### Regenerate and edit UI (feature 1)

- **Assistant bubble context menu:** Regenerate, and "Regenerate with…" (a submenu of `store.availableChatModels`).
- **Version arrows:** `‹ i/n ›` appear under the bubble when `versions.count > 1`. The selected version's model name shows when it differs from the current default.
- **User bubble context menu:** Edit. It opens the composer pre-filled, with a banner "Editing — later replies will be removed". Send shows a confirmation, then edits and resends.
- All of these actions are disabled while `engine.isGenerating`.

---

## 5. Testing, gates, and App Review

### New unit tests

| Suite | Covers |
|---|---|
| `ChatTurnEngineTests` | Scripted `MockInferenceService`: plain answer; stop mid-stream (single `finish`, notice, no fallback, no voice); tool call then answer; unknown tool (failed activity, non-empty text); direct calculator answer; empty output with search off; regenerate writes a new version; model override is used |
| `AnswerVersionTests` | First regenerate snapshots v0; select mirrors; cap of 5; persistence round-trip; legacy decode |
| `EditMessageTests` | Edited message and later messages removed; returned attachments intact; non-user message rejected with no change |
| `MemoryStoreTests` | CRUD, cap, persistence, budget trimming per tier, prompt section format |
| `DocumentChunkerTests` | Paragraph and sentence boundaries, overlap, page numbers, very long single paragraph |
| `DocumentSearchTests` | Ranking on a fixed fixture with a stub embedder; BM25-only path; disabled documents excluded |
| `ToolRegistryTests` (extended) | `search_documents` gating |
| `ShareInboxTests` | Payload round-trip, stale-item cleanup, routing to library or chat |
| `DeepLinkRouterTests` | Every route plus malformed URLs |
| `ChatExporterTests` | Markdown structure, thinking toggle, sources |
| `ModelSuggestionAdvisorTests` | Each rule, priority order, no suggestion when the current model is fine |

### Gates after every step

1. The full `xcodebuild test` suite is green.
2. `python3 scripts/verify_docs_freshness.py` shows 0 errors (update README test counts and similar).
3. The Release build on the iPhone 17 Pro (iOS 26.6.1) stays alive for more than 30 seconds with an existing chat, and no new `EdgeMindAi-*.ips` report appears.
4. Commit.

The model audit (`--localai-run-model-audit --localai-audit-require-installed`) is re-run after step 0 and after step 5; results must not regress.

### Manual device checks

| Step | Check |
|---|---|
| 1 | Regenerate, regenerate with another model, swipe versions, relaunch and versions persist; edit and resend |
| 2 | Export Markdown and PDF with an image and sources; open in Files |
| 3 | Attach an image with a non-vision model and the banner appears; switch |
| 4 | Add a memory, ask a question that uses it, see the chip; "remember that…" card |
| 5 | Import a 100+ page PDF; UI stays responsive; ask about page content and the citation shows the page |
| 6 | Share a PDF from Files with Summarize; share text with Ask; Siri Shortcut with Apple Intelligence (answers inline) and with a large model (opens the app) |
| 7 | Add small, medium, and lock-screen widgets; each button opens the right mode |

### App Review and privacy

- **`APP_STORE_REVIEW_NOTES.md`:** how to test the Share Extension, widget, document search (sample PDF steps), memory, and Shortcuts, with the note that no account is required.
- **`docs/privacy.html` and `APP_STORE_LISTING.md`:**
  - documents, embeddings, and memories stay on the device
  - no new data is collected
  - Apple's NaturalLanguage asset download is system-managed and sends no user content
- **`PrivacyInfo.xcprivacy`:** check required-reason APIs for the new targets (UserDefaults via the App Group, file timestamps).
- **Signing:** the new targets use the team `43NV5DTHKG` with automatic signing and the App Group capability, and each gets its own bundle ID:
  - `com.vinothrajalingam.EdgeMindAi.Share`
  - `com.vinothrajalingam.EdgeMindAi.Widget`
- **`AGENTS.md`:** architecture sections for the engine, versions, memory, documents, extensions, and deep links. `CLAUDE.md` gets a short summary.

## Out of scope

- Branching conversation trees
- Automatic memory extraction
- Answering inside the Share Extension
- Fetching shared URLs
- Showing chat content in widgets
- iCloud sync
- Sharing the chat store with extensions
