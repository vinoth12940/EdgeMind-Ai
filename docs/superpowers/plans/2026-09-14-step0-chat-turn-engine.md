# Step 0: ChatTurnEngine Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the chat turn pipeline out of `ChatView` into a testable `ChatTurnEngine`, with **no user-visible behavior change**.

**Architecture:**
- A `@MainActor @Observable` `ChatTurnEngine` owns the inference services and generation state, and runs the turn pipeline.
- The pipeline covers preflight, context and tools, stream, tool loop, fallbacks, and finish.
- All writes go through a `TurnOutput` protocol. `StoreTurnOutput` maps each call 1:1 onto today's `AppStateStore` calls.
- Dependencies are injected so unit tests can drive scripted streams without real models.
- `ChatView` keeps only UI state and calls the engine.

**Tech Stack:** Swift 5.10, SwiftUI, Observation, XCTest. XcodeGen (`project.yml`); no project changes are needed because the sources are folder-globbed.

**Spec:** `docs/superpowers/specs/2026-09-14-v031-feature-release-design.md` (§2 ChatTurnEngine, §5 Testing).

## Global Constraints

- iOS deployment target 17.0; `SWIFT_VERSION: 5.10`. Never edit `.xcodeproj`. Run `xcodegen generate` only if `project.yml` changes; this step does not change it.
- Keep the simulator guards `#if canImport(MLXLLM) && !targetEnvironment(simulator)` intact.
- `InferenceBudget` is the only source of context and token limits. Do not hardcode new limits.
- **No behavior change.** Every branch, condition, message string, and flush rule in the moved code is preserved exactly as of commit `a538da1`, the base of this branch.
- Exactly one `finish` per turn on every path (the spec §2 invariant).
- Test command (simulator): `xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -destination 'platform=iOS Simulator,name=EdgeMindAi iPhone 17 Pro Max'`
- Single class: append `-only-testing EdgeMindAiTests/ChatTurnEngineTests`.
- If simulator tests fail with a foreign `persistedSelectedSessionID`, run `xcrun simctl spawn 5DA41EAE-5B12-48A8-847B-D642F8E7D930 defaults delete com.vinothrajalingam.EdgeMindAi`.
- Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Work on branch `feature/v031-release-features`.

## File Structure

| File | Responsibility |
|---|---|
| Create `EdgeMindAi/Services/Chat/TurnOutput.swift` | `TurnOutput` protocol and `StoreTurnOutput` (writes to `AppStateStore`; single-finish guard) |
| Create `EdgeMindAi/Services/Chat/ChatTurnEngine.swift` | Engine state, dependencies, `send`/`stop`/`handleMemoryWarning`/`prewarm`, preflight, main stream, finish, idle release |
| Create `EdgeMindAi/Services/Chat/ChatTurnEngine+Tools.swift` | Tool loop, follow-up stream consumer, tool helper statics (moved from `ChatView`) |
| Create `EdgeMindAi/Services/Chat/ChatTurnEngine+Fallbacks.swift` | Post-stream missed-tool-call search, OpenELM retry, search-grounding retry, empty-output retries (moved from `ChatView`) |
| Create `EdgeMindAiTests/ChatTurnEngineTests.swift` | Scripted-stream engine tests |
| Create `EdgeMindAiTests/Support/ScriptedInferenceService.swift` | Test double: queue of event scripts, records calls, supports a "hang until cancelled" script |
| Modify `EdgeMindAi/App/EdgeMindAiApp.swift` | Create and inject the engine |
| Modify `EdgeMindAi/Features/Chat/ChatView.swift` | Remove moved state and functions; call the engine |
| Modify `README.md`, `AGENTS.md` | Test count; architecture note for the engine |

`EdgeMindAiTests/Support/` is inside the globbed `EdgeMindAiTests` source path, so no `project.yml` change is needed.

---

### Task 1: TurnOutput, engine core, and core tests

**Files:**
- Create: `EdgeMindAi/Services/Chat/TurnOutput.swift`
- Create: `EdgeMindAi/Services/Chat/ChatTurnEngine.swift`
- Create: `EdgeMindAiTests/Support/ScriptedInferenceService.swift`
- Create: `EdgeMindAiTests/ChatTurnEngineTests.swift`

**Interfaces:**
- Consumes (existing):
  - `AppStateStore` mutations (`appendMessage`, `removeMessage`, `updateMessageText`, `updateMessageThinking`, `updateMessageToolActivities`, `updateMessageCitations`, `updateMessageGenerationDuration`, `updateMessageStats`)
  - `InferenceService.generateStream(...)`
  - `RuntimeMemoryCoordinator.prepareForRuntime(_:)` and `releaseAll()`
  - `ResponsibleAIGuard.evaluate(prompt:)`
  - `ChatInputCapability`, `ChatVisionContext`, `DocumentExtractionService.promptContext(from:)`
- Produces (used by Tasks 2–4):
  - `TurnOutput` (below)
  - `ChatTurnEngine.Dependencies`
  - `ChatTurnEngine.init(store:dependencies:)`
  - `send(_ request: TurnRequest)`, `stop()`, `handleMemoryWarning()`, `prewarmDefaultModel()`, `waitUntilIdle() async`
  - `isGenerating: Bool` (observable), `speaker: ((String, AppSettings) -> Void)?`
  - internal `streamUpdateInterval: Duration`, `profileStore: RuntimeProfileStore`
  - internal `resolved(for:)`, `canUseToolLoop(model:resolved:imageData:)`
  - internal `resolvedAssistantText(from:prompt:thinkingSeen:)`, `searchAwareAssistantText(from:prompt:thinkingSeen:searchContext:)`, `cleanedDisplayedAssistantText(_:)`
  - internal `currentInterruptionNotice() -> String`
  - `func preflightBlockMessage(hasImage: Bool) -> String?`: the no-model / memory-guard / image-unsupported message `send` would write, or `nil` (used by `ChatView` in Task 4)

- [ ] **Step 1: Create the test double**

`EdgeMindAiTests/Support/ScriptedInferenceService.swift`:

```swift
import Foundation
@testable import EdgeMindAi

/// Returns one scripted event list per `generateStream` call, in order.
/// A script of `nil` produces a stream that emits `firstChunk` and then stays
/// open until the consuming task is cancelled (simulates a long generation).
final class ScriptedInferenceService: InferenceService, @unchecked Sendable {
    struct Call {
        let prompt: String
        let systemPrompt: String
        let conversation: [ChatMessage]
        let imageData: Data?
    }

    private var scripts: [[StreamEvent]?]
    private(set) var calls: [Call] = []
    let firstChunk: String

    init(scripts: [[StreamEvent]?], firstChunk: String = "partial") {
        self.scripts = scripts
        self.firstChunk = firstChunk
    }

    func generateReply(
        prompt: String, model: InstalledModel, conversation: [ChatMessage],
        searchContext: SearchContext?, systemPrompt: String, imageData: Data?, settings: AppSettings?
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, text: "unused")
    }

    func generateStream(
        prompt: String, model: InstalledModel, conversation: [ChatMessage],
        searchContext: SearchContext?, systemPrompt: String, imageData: Data?, settings: AppSettings?
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        calls.append(Call(prompt: prompt, systemPrompt: systemPrompt, conversation: conversation, imageData: imageData))
        let script = scripts.isEmpty ? [.textDelta("unscripted"), .done(GenerationStats(totalDuration: 0))] : scripts.removeFirst()
        let chunk = firstChunk
        let stream = AsyncStream<StreamEvent> { continuation in
            guard let script else {
                continuation.yield(.textDelta(chunk))
                return   // never finishes; ends when the consumer is cancelled
            }
            for event in script { continuation.yield(event) }
            continuation.finish()
        }
        return (UUID(), stream)
    }
}
```

- [ ] **Step 2: Write the failing core tests**

`EdgeMindAiTests/ChatTurnEngineTests.swift`:

```swift
import XCTest
@testable import EdgeMindAi

@MainActor
final class ChatTurnEngineTests: XCTestCase {
    private var session: ChatSession!
    private var store: AppStateStore!
    private var spoken: [String] = []

    override func setUp() async throws {
        clearPersistedStore()
        session = ChatSession(title: "New Chat", modelID: nil, messages: [])
        store = AppStateStore(chatSessions: [session], settings: .default)
        store.selectedSessionID = session.id
        spoken = []
    }

    override func tearDown() async throws {
        clearPersistedStore()
    }

    // MARK: helpers

    private func clearPersistedStore() {
        let defaults = UserDefaults.standard
        for key in ["persistedInstalledModels", "persistedAppSettings", "persistedChatSessions", "persistedSelectedSessionID"] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Apple Intelligence entry from the real catalog: no tool calling, always "installed".
    private var appleModel: InstalledModel {
        store.installedModels.first { $0.catalogItem.runtimeType == .foundationModels }!
    }

    /// A tool-verified catalog model (Qwen 3.5 VL 0.8B, profile verifiedToolCalling = xmlToolCall).
    private var toolModel: InstalledModel {
        let item = store.catalog.first { $0.id.uuidString == "24909990-2689-505F-AFE9-EC84DEA3EA8A" }!
        return InstalledModel(catalogItem: item, installState: .installed, progress: 1, localPath: item.mlxModelID)
    }

    private func makeEngine(
        model: InstalledModel?,
        service: InferenceService,
        memoryGuard: String? = nil
    ) -> ChatTurnEngine {
        let engine = ChatTurnEngine(
            store: store,
            dependencies: .init(
                resolveModel: { _ in model },
                serviceForModel: { _ in service },
                prepareRuntime: { _ in },
                releaseAllRuntimes: { },
                memoryGuardMessage: { _, _ in memoryGuard },
                idleReleaseDelay: .seconds(3600)
            )
        )
        engine.speaker = { [weak self] text, _ in self?.spoken.append(text) }
        return engine
    }

    private func request(_ prompt: String) -> TurnRequest {
        TurnRequest(sessionID: session.id, prompt: prompt, attachments: [], image: nil, liveSearchEnabled: false)
    }

    private var messages: [ChatMessage] {
        store.chatSessions.first { $0.id == session.id }?.messages ?? []
    }

    // MARK: tests

    func test_plainAnswer_appendsUserAndAssistantWithStats() async {
        let stats = GenerationStats(timeToFirstToken: 0.1, totalDuration: 1, outputTokens: 3, deltaCount: 2)
        let service = ScriptedInferenceService(scripts: [[.textDelta("Hello "), .textDelta("there"), .done(stats)]])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("Hi"))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages[0].text, "Hi")
        XCTAssertEqual(messages[1].text, "Hello there")
        XCTAssertEqual(messages[1].stats, stats)
        XCTAssertNotNil(messages[1].generationDurationSeconds)
        XCTAssertFalse(engine.isGenerating)
    }

    func test_noModel_appendsNoModelMessageWithoutUserMessage() async {
        let engine = makeEngine(model: nil, service: ScriptedInferenceService(scripts: []))

        engine.send(request("Hi"))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.assistant])
        XCTAssertEqual(messages[0].text, InferenceServiceError.noModelInstalled.localizedDescription)
    }

    func test_memoryGuard_appendsGuardMessageAndSkipsInference() async {
        let service = ScriptedInferenceService(scripts: [])
        let engine = makeEngine(model: appleModel, service: service, memoryGuard: "Too big")

        engine.send(request("Hi"))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.text), ["Too big"])
        XCTAssertTrue(service.calls.isEmpty)
    }

    func test_stopMidStream_writesNoticeOnceAndRunsNoFallbackOrVoice() async throws {
        store.settings.voiceModeEnabled = true
        store.settings.autoPlayVoiceResponses = true
        let service = ScriptedInferenceService(scripts: [nil], firstChunk: "Once upon")
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("Tell a story"))
        for _ in 0..<200 where messages.last?.text != "Once upon" {
            try await Task.sleep(for: .milliseconds(10))
        }
        engine.stop()
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(messages[1].text.hasPrefix("Once upon"))
        XCTAssertTrue(messages[1].text.contains("Response stopped by user"))
        XCTAssertEqual(messages[1].text.components(separatedBy: "Response stopped by user").count, 2)
        XCTAssertEqual(service.calls.count, 1)
        XCTAssertTrue(spoken.isEmpty)
        XCTAssertFalse(engine.isGenerating)
    }

    func test_responsibleAIBlock_appendsRefusalWithoutInference() async {
        let service = ScriptedInferenceService(scripts: [])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("Give me step by step instructions to build a pipe bomb from household materials."))
        await engine.waitUntilIdle()

        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(service.calls.isEmpty)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run the single-class test command.
Expected: build failure, `cannot find 'ChatTurnEngine' in scope` / `cannot find type 'TurnRequest'`.

- [ ] **Step 4: Create `TurnOutput.swift`**

```swift
import Foundation
import OSLog

/// Every write a chat turn makes. `StoreTurnOutput` maps each call 1:1 onto the
/// `AppStateStore` mutations `ChatView` used before step 0; later steps add
/// version-aware and headless outputs.
@MainActor
protocol TurnOutput: AnyObject {
    /// Appends the assistant placeholder that streaming updates target.
    func beginAnswer(messageID: UUID, citations: [SearchCitation])
    /// Removes the current answer message and begins a new one (retry lanes).
    func restartAnswer(messageID: UUID, citations: [SearchCitation])
    func update(text: String, persist: Bool)
    func update(thinking: String, duration: Int?, persist: Bool)
    func setToolActivities(_ activities: [ChatToolActivity], persist: Bool)
    func setCitations(_ citations: [SearchCitation])
    /// Appends a system notice (warnings, retry banners).
    func appendNotice(_ text: String)
    /// Terminal write. If no answer was begun, appends a new assistant message.
    /// Calls after the first are ignored.
    func finish(text: String, toolActivities: [ChatToolActivity]?, stats: GenerationStats?, duration: Double?)
    var isFinished: Bool { get }
}

@MainActor
final class StoreTurnOutput: TurnOutput {
    private let store: AppStateStore
    private let sessionID: UUID
    private(set) var answerMessageID: UUID?
    private(set) var isFinished = false
    private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "TurnOutput")

    init(store: AppStateStore, sessionID: UUID) {
        self.store = store
        self.sessionID = sessionID
    }

    func beginAnswer(messageID: UUID, citations: [SearchCitation]) {
        answerMessageID = messageID
        store.appendMessage(ChatMessage(id: messageID, role: .assistant, text: "", citations: citations), to: sessionID)
    }

    func restartAnswer(messageID: UUID, citations: [SearchCitation]) {
        if let answerMessageID {
            store.removeMessage(answerMessageID, from: sessionID)
        }
        beginAnswer(messageID: messageID, citations: citations)
    }

    func update(text: String, persist: Bool) {
        guard let answerMessageID else { return }
        store.updateMessageText(answerMessageID, in: sessionID, text: text, persist: persist)
    }

    func update(thinking: String, duration: Int?, persist: Bool) {
        guard let answerMessageID else { return }
        store.updateMessageThinking(answerMessageID, in: sessionID, thinkingContent: thinking, thinkingDurationSeconds: duration, persist: persist)
    }

    func setToolActivities(_ activities: [ChatToolActivity], persist: Bool) {
        guard let answerMessageID else { return }
        store.updateMessageToolActivities(answerMessageID, in: sessionID, toolActivities: activities, persist: persist)
    }

    func setCitations(_ citations: [SearchCitation]) {
        guard let answerMessageID else { return }
        store.updateMessageCitations(answerMessageID, in: sessionID, citations: citations, persist: true)
    }

    func appendNotice(_ text: String) {
        store.appendMessage(ChatMessage(role: .system, text: text), to: sessionID)
    }

    func finish(text: String, toolActivities: [ChatToolActivity]?, stats: GenerationStats?, duration: Double?) {
        guard !isFinished else {
            logger.error("finish called twice; ignoring second call")
            return
        }
        isFinished = true
        guard let answerMessageID else {
            store.appendMessage(
                ChatMessage(role: .assistant, text: text, toolActivities: toolActivities ?? []),
                to: sessionID
            )
            return
        }
        if let duration {
            store.updateMessageGenerationDuration(answerMessageID, in: sessionID, duration: duration, persist: true)
        }
        store.updateMessageStats(answerMessageID, in: sessionID, stats: stats, persist: true)
        store.updateMessageText(answerMessageID, in: sessionID, text: text, persist: true)
    }
}
```

- [ ] **Step 5: Create `ChatTurnEngine.swift` (core without tools and fallbacks)**

Move `GenerationInterruptionReason` (`ChatView.swift` lines 6–18) into this file as `enum GenerationInterruptionReason` (internal, not `private`). Delete it from `ChatView` in Task 4.

```swift
import Foundation
import Observation
import OSLog
import UIKit

let chatEngineLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "ChatTurnEngine")

enum GenerationInterruptionReason {
    case user
    case memoryWarning

    var notice: String {
        switch self {
        case .user:
            return "Response stopped by user"
        case .memoryWarning:
            return "Your device needed memory — response was interrupted"
        }
    }
}

struct TurnRequest {
    let sessionID: UUID
    let prompt: String
    let attachments: [ChatAttachment]
    /// Raw attached image; the engine encodes it with `encodedAttachmentData(from:model:)`.
    let image: UIImage?
    let liveSearchEnabled: Bool
}

@MainActor
@Observable
final class ChatTurnEngine {
    struct Dependencies {
        var resolveModel: @MainActor (AppStateStore) -> InstalledModel?
        var serviceForModel: @MainActor (InstalledModel) -> InferenceService
        var prepareRuntime: (ModelCatalogItem.RuntimeType) async -> Void
        var releaseAllRuntimes: () async -> Void
        /// (model, hasImage) -> blocking message, or nil to proceed.
        var memoryGuardMessage: @MainActor (InstalledModel, Bool) -> String?
        var idleReleaseDelay: Duration
    }

    private(set) var isGenerating = false
    /// Set by the view that owns the voice controller.
    @ObservationIgnored var speaker: ((String, AppSettings) -> Void)?

    @ObservationIgnored let store: AppStateStore
    @ObservationIgnored let dependencies: Dependencies
    @ObservationIgnored let profileStore = RuntimeProfileStore()
    @ObservationIgnored let streamUpdateInterval: Duration = .milliseconds(80)

    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var activeGenerationID: UUID?
    @ObservationIgnored private var interruptionReason: GenerationInterruptionReason?
    @ObservationIgnored private var idleRuntimeReleaseTask: Task<Void, Never>?
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?

    init(store: AppStateStore, dependencies: Dependencies) {
        self.store = store
        self.dependencies = dependencies
    }

    func resolved(for model: InstalledModel) -> ResolvedModel {
        ModelRuntimeResolver.resolve(catalog: model.catalogItem, store: profileStore)
    }

    func currentInterruptionNotice() -> String {
        (interruptionReason ?? .user).notice
    }

    /// Test hook: waits for the in-flight turn (if any) to complete.
    func waitUntilIdle() async {
        await generationTask?.value
    }
}
```

Add `static func live() -> Dependencies` in an extension in the same file, built from the code currently in `ChatView`:
- `resolveModel: { $0.defaultModel }`
- `serviceForModel`: the `switch` from `ChatView.inferenceServiceForModel` (lines 212–223). Hold the four services in a `LiveServices` final class so the instances persist: `LocalLlamaInferenceService()`, `MLXInferenceService()`, `LiteRTInferenceService()`, `AppleFoundationInferenceService()`.
- `prepareRuntime: { await RuntimeMemoryCoordinator.prepareForRuntime($0) }`
- `releaseAllRuntimes: { await RuntimeMemoryCoordinator.releaseAll() }`
- `memoryGuardMessage`: the body of `ChatView.memoryGuardMessage(for:)` (lines 189–203), with `attachedImage != nil` replaced by the `hasImage` parameter
- `idleReleaseDelay: .seconds(90)`

Add these methods, **moved from `ChatView`** with the renames shown:

| From `ChatView` (line) | To engine | Change |
|---|---|---|
| `stopGeneration()` (1219) | `func stop()` | `isSending = false` → `isGenerating = false` |
| `handleMemoryWarning()` (1228) | `func handleMemoryWarning()` | `store.selectedSession?.id` notice append unchanged; `RuntimeMemoryCoordinator.releaseAll()` → `dependencies.releaseAllRuntimes()` |
| `prewarmSelectedModel()` (230) | `func prewarmDefaultModel()` | `RuntimeMemoryCoordinator.prepareForRuntime` → `dependencies.prepareRuntime` |
| `scheduleIdleRuntimeRelease()` (1861) | `private func scheduleIdleRuntimeRelease()` | sleep `dependencies.idleReleaseDelay`; release via `dependencies.releaseAllRuntimes()` |
| `finishGenerationIfCurrent(_:)` (1876) | `func finishGenerationIfCurrent(_:)` | `isSending` → `isGenerating` |
| `canUseToolLoop(...)` (1313) | same, internal | none |
| `cleanedDisplayedAssistantText`, `resolvedAssistantText`, `searchAwareAssistantText` (1796–1827) | same, internal | none |
| `encodedAttachmentData(from:model:)`, `downsampleImage` (1829–1858) | `static func encodedAttachmentData(from:model:)`, `nonisolated static func downsampleImage` | make static |
| `friendlyInferenceError` (1682) | `static func friendlyInferenceError` | none |

Implement `send(_:)` by moving `ChatView.sendPrompt()` (line 1891 to the end of its body, just before `static func looksLikeRealTimeQuery`), with these exact transformations:
1. **Guard.** Replace `guard !isSending else { return }` with `guard !isGenerating else { return }`. Remove `voiceController.stopListening()` (the view does it). Remove the reads of `prompt`, `attachedImage`, `attachedDocuments`. Use `request.prompt` (already trimmed by the view), `request.image`, and `request.attachments`. Remove the view-state resets (`isInputFocused`, `prompt = ""`, `attachedImage = nil`, `attachedDocuments = []`); the view does those.
2. **Session.** Replace `if store.selectedSession == nil { store.createSession(...) }` / `guard let sessionID = store.selectedSession?.id` with `let sessionID = request.sessionID`. Create `let output = StoreTurnOutput(store: store, sessionID: sessionID)`.
3. **Model.** `store.defaultModel` → `dependencies.resolveModel(store)`.
4. **Early exits.** The no-model, memory-guard, and image-unsupported branches become `output.finish(text: <same message>, toolActivities: nil, stats: nil, duration: nil); return`. The memory guard calls `dependencies.memoryGuardMessage(model, request.image != nil)`. These run before the user message is appended, exactly as today.
5. **RAI block.** `store.appendMessage(ChatMessage(role: .assistant, text: response), ...)` → `output.finish(text: response, toolActivities: nil, stats: nil, duration: nil)`.
6. **Start.** `isSending = true` → `isGenerating = true`. `RuntimeMemoryCoordinator.prepareForRuntime` → `dependencies.prepareRuntime`.
7. **Services.** `inferenceServiceForModel(model)` → `dependencies.serviceForModel(model)`. `liveSearchEnabled` → `request.liveSearchEnabled`.
8. **Placeholder.** `store.appendMessage(placeholder, to: sessionID)` → `output.beginAnswer(messageID: messageID, citations: pendingCitations)`.
9. **Store writes** anywhere in the moved body:

   | Before | After |
   |---|---|
   | `updateStreamingMessage(t, messageID: _, sessionID: _, persist: p)` or `store.updateMessageText(_, in: _, text: t, persist: p)` | `output.update(text: t, persist: p)` |
   | `store.updateMessageThinking(_, in: _, thinkingContent: c, thinkingDurationSeconds: d, persist: p)` | `output.update(thinking: c, duration: d, persist: p)` (missing `d` → `nil`, missing `p` → `false`) |
   | `store.updateMessageToolActivities(_, in: _, toolActivities: a[, persist: p])` | `output.setToolActivities(a, persist: p ?? false)` |
   | `store.updateMessageCitations(...)` | `output.setCitations(c)` |
   | `store.appendMessage(ChatMessage(role: .system, text: x), to: sessionID)` (any `let` holding such a message) | `output.appendNotice(x)` |
   | `store.removeMessage(messageID, ...)` immediately followed by generating a retry stream and `store.appendMessage(retryPlaceholder, ...)` | keep the order "remove → notice → generate"; replace the remove with nothing and the placeholder append with `output.restartAnswer(messageID: retryMsgID, citations: <same citations>)` |

   `await MainActor.run { ... }` wrappers around these calls may stay or be unwrapped; the engine is `@MainActor`.
10. **Upfront direct answer.** The non-tool branch's `store.appendMessage(message)` with `toolActivities` becomes `output.finish(text: directAnswer, toolActivities: upfront.map { Self.toolActivity(from: $0, model: model) }, stats: nil, duration: nil)`, then `finishGenerationIfCurrent(taskID)` and `return`.
11. **Terminal writes.** Every terminal write of the final text (with or without duration and stats) becomes one `output.finish(text: finalText, toolActivities: nil, stats: <captured or nil>, duration: <measured or nil>)`:
    - main path: `updateMessageGenerationDuration` + `updateMessageStats` + `updateStreamingMessage(persist: true)`
    - each retry lane's final `updateStreamingMessage(..., persist: true)`
    - the post-stream fallback's final write
    - the stopped-by-user path

    On the main path, pass `duration: nil, stats: nil` when `stoppedByUser`, matching today.
12. **Voice.** `voiceController.speak(persistedFinalText, using: store.settings)` → `speaker?(persistedFinalText, store.settings)`. Conditions unchanged.
13. **Error path.** The `catch` appends `output.appendNotice(friendlyError)`. Then, if `!output.isFinished`, call `output.finish(text: <current accumulated or empty-output message>, ...)`: use `AssistantResponseFallback.emptyOutputMessage(thinkingSeen: false)` if the answer text is empty. Finally call `finishGenerationIfCurrent(taskID)`.

    **Clarification (single-finish invariant):** before step 0, an error after `beginAnswer` left an empty bubble. Finishing it with the empty-output text is the only intended visible change in step 0, and it is required by spec §2.
14. **Interruption notice.** `currentGenerationInterruptionNotice()` → `currentInterruptionNotice()`.
15. **Task handle.** `generationTask = task` is kept at the end.

**Task 1 moves the entire pipeline.** Move `runToolLoop`, `consumeFollowupStream`, and the tool helper statics into `ChatTurnEngine+Tools.swift` now, applying the Task 2 Step 3 substitutions. Leave the post-stream lanes inline in `send` (Task 3 extracts them). By the end of Task 1 the full body of `sendPrompt` is in the engine, so no behavior is lost. Tasks 2 and 3 add tests and do the lane extraction.

- [ ] **Step 6: Run the core tests**

Run the single-class test command.
Expected: 5 tests pass.

- [ ] **Step 7: Run the full suite**

Run the full test command.
Expected: all existing tests plus 5 new ones pass. `ChatView` still has its own copy of the pipeline and is untouched in this task.

- [ ] **Step 8: Commit**

```bash
git add EdgeMindAi/Services/Chat EdgeMindAiTests/Support EdgeMindAiTests/ChatTurnEngineTests.swift
git commit -m "refactor(chat): add ChatTurnEngine and TurnOutput with scripted-stream tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Tool loop in the engine and tool tests

**Files:**
- Create or complete: `EdgeMindAi/Services/Chat/ChatTurnEngine+Tools.swift`
- Modify: `EdgeMindAiTests/ChatTurnEngineTests.swift`

**Interfaces:**
- Consumes (Task 1): `TurnOutput`, `ChatTurnEngine` internals listed in Task 1, `streamUpdateInterval`, `searchAwareAssistantText`, `cleanedDisplayedAssistantText`.
- Produces:
  - `func runToolLoop(toolName:argsJSON:output:sessionID:model:service:conversation:inferencePrompt:trimmedPrompt:effectiveImageData:baseSystemPrompt:toolContext:taskID:clock:lastFlush:) async -> ToolLoopOutcome`
  - `func consumeFollowupStream(_:output:clock:lastFlush:streamsToUI:updatesThinking:) async -> (text: String, thinking: String)`
  - statics `toolActivity(from:model:duration:)` and `toolActivity(name:output:model:status:duration:)`, `boundToolOutputForContext`, `directToolAnswer`, `fallbackToolAnswer`, `toolDisplayName`, `toolRunningOutput`, `toolStatusMessage`, `extractToolCallQuery`, `parseWebSearchQuery`

- [ ] **Step 1: Write the failing tool tests**

Append to `ChatTurnEngineTests`:

```swift
    func test_toolCall_thenAnswer_writesActivityAndFinalText() async {
        let service = ScriptedInferenceService(scripts: [
            [.toolCall(name: "search_chats", argsJSON: "{\"query\": \"recipe\"}")],
            [.textDelta("No earlier chats mention that."), .done(GenerationStats(totalDuration: 1))]
        ])
        let engine = makeEngine(model: toolModel, service: service)

        engine.send(request("did we talk about a recipe before"))
        await engine.waitUntilIdle()

        let answer = messages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.toolActivities.first?.name, "search_chats")
        XCTAssertNotEqual(answer?.toolActivities.first?.status, .running)
        XCTAssertEqual(answer?.text, "No earlier chats mention that.")
        XCTAssertEqual(service.calls.count, 2)
        XCTAssertTrue(service.calls.first?.systemPrompt.contains("# Tools") ?? false)
    }

    func test_unknownTool_marksFailedAndNeverLeavesEmptyAnswer() async {
        let service = ScriptedInferenceService(scripts: [[.toolCall(name: "launch_rockets", argsJSON: "{}")]])
        let engine = makeEngine(model: toolModel, service: service)

        engine.send(request("do the thing"))
        await engine.waitUntilIdle()

        let answer = messages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.toolActivities.last?.status, .failed)
        XCTAssertFalse(answer?.text.isEmpty ?? true)
        XCTAssertTrue(messages.contains { $0.role == .system && $0.text.contains("Unknown tool: launch_rockets") })
        XCTAssertFalse(engine.isGenerating)
    }

    func test_calculateTool_returnsDirectAnswerWithoutSecondPass() async {
        let service = ScriptedInferenceService(scripts: [
            [.toolCall(name: "calculate", argsJSON: "{\"expression\": \"6*7\"}")]
        ])
        let engine = makeEngine(model: toolModel, service: service)

        engine.send(request("use the calculator for six times seven"))
        await engine.waitUntilIdle()

        XCTAssertEqual(service.calls.count, 1)
        XCTAssertTrue(messages.last { $0.role == .assistant }?.text.contains("42") ?? false)
    }

    func test_toolLoopCap_writesNonEmptyAnswerAndCapNotice() async {
        let loop: [StreamEvent] = [.toolCall(name: "search_chats", argsJSON: "{\"query\": \"again\"}")]
        let service = ScriptedInferenceService(scripts: [loop, loop, loop, loop])
        let engine = makeEngine(model: toolModel, service: service)

        engine.send(request("search my chats repeatedly"))
        await engine.waitUntilIdle()

        XCTAssertTrue(messages.contains { $0.text.contains("Reached the tool-call limit") })
        XCTAssertFalse(messages.last { $0.role == .assistant }?.text.isEmpty ?? true)
    }
```

`search_chats` is used for the loop tests because it is not in `directToolAnswer`'s list (`calculate`, `get_current_time`, `get_device_info`, and `get_battery_level` return directly with no second pass). `search_chats` is available because the test store has one session. `CalculateTool` accepts `{"expression": "..."}`.

- [ ] **Step 2: Prove the tests can fail**

Because Task 1 already moved the real tool code, these tests should pass as soon as they're added. Before trusting them, prove each can fail:
1. Temporarily make `directToolAnswer` return `nil`, run the class, and confirm `test_calculateTool_returnsDirectAnswerWithoutSecondPass` fails (2 calls).
2. Temporarily delete the unknown-tool `visibleToolActivities[...] = ... .failed` replacement and confirm `test_unknownTool_marksFailedAndNeverLeavesEmptyAnswer` fails.
3. Restore both.

- [ ] **Step 3: Tool-code substitutions (applied during Task 1; verify here)**

Move from `ChatView` into `ChatTurnEngine+Tools.swift` as `extension ChatTurnEngine`:
- `extractToolCallQuery` and `parseWebSearchQuery` (1270–1311)
- `consumeFollowupStream` (1330–1380)
- `ToolLoopOutcome` (1385)
- `runToolLoop` (1395–1639)
- `continuationPrompt` (1640)
- the statics at 1644–1795

Apply the Task 1 step 9 write table. Specifically:
- `runToolLoop` and `consumeFollowupStream` take `output: TurnOutput` instead of `messageID`/`sessionID`.
- `store.appendMessage(unknownMsg)`, `errMsg`, and `capMsg` → `output.appendNotice(...)`.
- The loop's final `updateStreamingMessage(visibleText, persist: true)`, `updateMessageGenerationDuration`, and `updateMessageStats` → `output.finish(text: visibleText, toolActivities: nil, stats: capturedStats, duration: genDuration)`.
- The cap path and the aborted path → `output.finish(text: <visible text>, toolActivities: nil, stats: nil, duration: nil)`.
- The direct-answer path → `output.finish(text: directAnswer, toolActivities: nil, stats: nil, duration: nil)`.
- Remove the unused `availableTools` parameter from `runToolLoop` and from its call site in `send`.

- [ ] **Step 4: Run the engine tests**

Run the single-class test command.
Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add EdgeMindAi/Services/Chat EdgeMindAiTests/ChatTurnEngineTests.swift
git commit -m "refactor(chat): move tool loop into ChatTurnEngine with tool-path tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Fallback lanes in the engine and fallback tests

**Files:**
- Create or complete: `EdgeMindAi/Services/Chat/ChatTurnEngine+Fallbacks.swift`
- Modify: `EdgeMindAiTests/ChatTurnEngineTests.swift`

**Interfaces:**
- Consumes (Tasks 1–2): `consumeFollowupStream`, `extractToolCallQuery`, `TurnOutput.restartAnswer`, `finish`.
- Produces: `func runPostStreamLanes(context: PostStreamContext) async -> Bool` (`true` means a lane handled and finished the turn), with:

```swift
struct PostStreamContext {
    let output: TurnOutput
    let taskID: UUID
    let model: InstalledModel
    let service: InferenceService
    let conversation: [ChatMessage]
    let inferencePrompt: String
    let trimmedPrompt: String
    let effectiveImageData: Data?
    let searchContext: SearchContext?
    let modelCanUseToolLoop: Bool
    let accumulated: String
    let finalText: String
    let stoppedByUser: Bool
    let clock: ContinuousClock
    let lastFlush: ContinuousClock.Instant
}
```

- [ ] **Step 1: Write the failing fallback tests**

```swift
    func test_emptyOutput_withoutSearch_finishesWithEmptyOutputMessage() async {
        let service = ScriptedInferenceService(scripts: [[.done(GenerationStats(totalDuration: 0))]])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("say nothing"))
        await engine.waitUntilIdle()

        let answer = messages.last { $0.role == .assistant }
        XCTAssertTrue(AssistantResponseFallback.isEmptyOutputMessage(answer?.text ?? ""))
        XCTAssertEqual(service.calls.count, 1)
    }

    func test_upfrontLocalTool_forNonToolModel_answersDirectly() async {
        let service = ScriptedInferenceService(scripts: [])
        let engine = makeEngine(model: appleModel, service: service)

        engine.send(request("what is 12 * 12"))
        await engine.waitUntilIdle()

        let answer = messages.last { $0.role == .assistant }
        XCTAssertTrue(answer?.text.contains("144") ?? false)
        XCTAssertTrue(service.calls.isEmpty)
    }

    func test_modelFailure_appendsFriendlyErrorAndFinishesAnswer() async {
        final class FailingService: InferenceService {
            func generateReply(prompt: String, model: InstalledModel, conversation: [ChatMessage], searchContext: SearchContext?, systemPrompt: String, imageData: Data?, settings: AppSettings?) async throws -> ChatMessage { throw InferenceServiceError.missingLocalModelFile }
            func generateStream(prompt: String, model: InstalledModel, conversation: [ChatMessage], searchContext: SearchContext?, systemPrompt: String, imageData: Data?, settings: AppSettings?) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) { throw InferenceServiceError.missingLocalModelFile }
        }
        let engine = makeEngine(model: appleModel, service: FailingService())

        engine.send(request("hello there friend"))
        await engine.waitUntilIdle()

        XCTAssertTrue(messages.contains { $0.role == .system && $0.text.contains("model file") })
        XCTAssertFalse(engine.isGenerating)
    }
```

Before relying on `test_upfrontLocalTool_forNonToolModel_answersDirectly`, confirm that `UpfrontToolDetector.canHandleLocally(prompt:)` and `directAnswer(for:)` treat `"what is 12 * 12"` as a direct calculator answer. Read `EdgeMindAi/Services/Tools/UpfrontToolDetector.swift` and use a prompt it matches.

- [ ] **Step 2: Run them and confirm failures** where the lanes are still stubs. If the real code was already moved in Task 1, break one lane temporarily to see the test fail, then restore.

- [ ] **Step 3: Move the post-stream lanes**

From `send`, move everything from the `// ── Post-stream tool call fallback ──` comment through the end of the `// ── Empty-output fallback ──` block into `runPostStreamLanes(context:)`:
- post-stream missed-tool-call search
- OpenELM retry
- search-grounding retry
- empty-output branch A and branch B

Each lane that currently `return`s after `finishGenerationIfCurrent(taskID)` now calls `output.finish(...)` per the Task 1 table and returns `true`. `send` becomes:

```swift
if await runPostStreamLanes(context: PostStreamContext(/* current locals */)) {
    finishGenerationIfCurrent(taskID)
    return
}
```

Keep every lane condition byte-for-byte, including the `!stoppedByUser` guards.

- [ ] **Step 4: Run the engine tests**

Run the single-class test command.
Expected: 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add EdgeMindAi/Services/Chat EdgeMindAiTests/ChatTurnEngineTests.swift
git commit -m "refactor(chat): move post-stream fallback lanes into ChatTurnEngine with tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Wire `ChatView` to the engine, remove duplicates, update docs

**Files:**
- Modify: `EdgeMindAi/App/EdgeMindAiApp.swift`
- Modify: `EdgeMindAi/Features/Chat/ChatView.swift`
- Modify: `README.md` (unit test count), `AGENTS.md` (architecture)

**Interfaces:**
- Consumes: `ChatTurnEngine(store:dependencies: .live())`, `send`, `stop`, `handleMemoryWarning`, `prewarmDefaultModel`, `isGenerating`, `speaker`, `static encodedAttachmentData(from:model:)`.
- Produces: environment value `ChatTurnEngine`, which later steps read with `@Environment(ChatTurnEngine.self)`.

- [ ] **Step 1: Inject the engine** in `EdgeMindAiApp.swift`:

```swift
@State private var store: AppStateStore
@State private var authStore = AuthStateStore()
@State private var chatEngine: ChatTurnEngine

init() {
    UITabBar.appearance().isHidden = true
    let store = AppStateStore()
    _store = State(initialValue: store)
    _chatEngine = State(initialValue: ChatTurnEngine(store: store, dependencies: .live()))
}
```

Add `.environment(chatEngine)` next to `.environment(store)`. Replace the current `@State private var store = AppStateStore()`; the engine must share that exact store instance.

- [ ] **Step 2: Rewire `ChatView`**
- Add `@Environment(ChatTurnEngine.self) private var engine`.
- **Delete** these state properties:
  - `isSending`, `generationTask`, `activeGenerationID`, `generationInterruptionReason`
  - the four `*InferenceService` properties
  - `idleRuntimeReleaseTask`, `prewarmTask`
  - `private let profileStore` and `streamUpdateInterval`
- **Delete** these functions:
  - `inferenceServiceForModel`, `prewarmSelectedModel`, `memoryGuardMessage`
  - `stopGeneration`, `handleMemoryWarning`
  - `extractToolCallQuery` through `searchAwareAssistantText`
  - `encodedAttachmentData`, `downsampleImage`
  - `scheduleIdleRuntimeRelease`, `updateStreamingMessage`, `finishGenerationIfCurrent`, `currentGenerationInterruptionNotice`
  - the body of `sendPrompt`
  - the `GenerationInterruptionReason` enum
- Replace uses:

  | Before | After |
  |---|---|
  | `isSending` | `engine.isGenerating` |
  | `stopGeneration` / `stopGeneration()` | `engine.stop` / `engine.stop()` |
  | `handleMemoryWarning()` | `engine.handleMemoryWarning()` |
  | `prewarmSelectedModel()` | `engine.prewarmDefaultModel()` |
  | `profileStore` in `isVisionModel` / `runtimeNotice` / `resolved(for:)` | `engine.profileStore` |
  | `.onDisappear { idleRuntimeReleaseTask?.cancel() ... }` | remove the idle-task lines (the engine owns the idle release) |
  | scenePhase background `if !isSending && generationTask == nil` | `if !engine.isGenerating` |

- In `.onAppear`, add `engine.speaker = { [voiceController] text, settings in voiceController.speak(text, using: settings) }`.
- Replace `sendPrompt()` with:

```swift
private func sendPrompt() {
    guard !engine.isGenerating else { return }
    voiceController.stopListening()
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPrompt.isEmpty || attachedImage != nil || !attachedDocuments.isEmpty else { return }
    if store.selectedSession == nil {
        store.createSession(using: store.defaultModel?.catalogItem.id)
    }
    guard let sessionID = store.selectedSession?.id else { return }
    let request = TurnRequest(
        sessionID: sessionID,
        prompt: trimmedPrompt,
        attachments: attachedDocuments,
        image: attachedImage,
        liveSearchEnabled: liveSearchEnabled
    )
    isInputFocused = false
    prompt = ""
    attachedImage = nil
    attachedDocuments = []
    engine.send(request)
}
```

**Ordering note:** before step 0, the composer was cleared only *after* the early preflight exits (no model, memory guard, unsupported image). Those exits left the user's typed prompt in the composer. To preserve that, the engine exposes `func preflightBlockMessage(hasImage: Bool) -> String?` (from the Task 1 early-exit logic). `sendPrompt` calls it first; if it returns a message, it calls `engine.send(request)`, which writes the message, and does **not** clear the composer.

- [ ] **Step 3: Build and run the full suite**

Run the full test command.
Expected: every test passes (existing count + 12). Run `grep -n "RuntimeMemoryCoordinator\|generateStream\|runToolLoop" EdgeMindAi/Features/Chat/ChatView.swift`; the only acceptable hit is the model-picker `prepareForRuntime` call in `compactTopBar`.

- [ ] **Step 4: Docs**
- `README.md`: update the unit-test count to the new total, the number of `func test_` methods (`python3 scripts/verify_docs_freshness.py` reports the actual count).
- `AGENTS.md` → Key wiring points: replace the `ChatView.swift` bullet with a `ChatTurnEngine` bullet describing:
  - ownership of the services
  - `TurnOutput` / `StoreTurnOutput`
  - the single-finish invariant
  - `Dependencies.live()`
  - `ChatView` as UI-only

  Update the "Tool loop is bounded" gotcha: the loop lives in `ChatTurnEngine+Tools.swift`.
- Run `python3 scripts/verify_docs_freshness.py`. Expected: 0 errors.

- [ ] **Step 5: Device gate** (the controller runs this, not the implementer subagent, because the physical iPhone is required):

```bash
xattr -cr EdgeMindAi Vendor
xcodebuild -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -configuration Release \
  -destination 'id=00008150-00056CA11A6A401C' -allowProvisioningUpdates build
xcrun devicectl device install app --device 428A7E6B-8497-56D4-B7A2-02ABAD4FC996 \
  ~/Library/Developer/Xcode/DerivedData/EdgeMindAi-*/Build/Products/Release-iphoneos/EdgeMindAi.app
xcrun devicectl device process launch --terminate-existing --device 428A7E6B-8497-56D4-B7A2-02ABAD4FC996 com.vinothrajalingam.EdgeMindAi
```

Pass criteria:
- After 40 seconds, `devicectl device info processes` still lists `EdgeMindAi.app`.
- No new `EdgeMindAi-*.ips` appears in `devicectl device info files --domain-type systemCrashLogs`.
- The model audit for `Qwen 3.5 VL 0.8B` completes its cases. Verdicts may vary run to run (known model inconsistency), but no case fails with a crash or timeout.

- [ ] **Step 6: Commit**

```bash
git add EdgeMindAi/App/EdgeMindAiApp.swift EdgeMindAi/Features/Chat/ChatView.swift README.md AGENTS.md
git commit -m "refactor(chat): route ChatView through ChatTurnEngine; remove duplicated pipeline

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
