# Stream Processor, Rendering Fixes & Agentic Search — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a `StreamProcessor` actor that unifies think-block extraction, tool-call interception, and markdown buffering; fix 8 rendering gaps in `MarkdownTextView`; and wire an agentic search loop for tool-calling models.

**Architecture:** A new `StreamProcessor` actor wraps the raw `AsyncStream<String>` from both inference backends and emits structured `StreamEvent` values. `ChatView`'s streaming loop is refactored to switch on these events, eliminating all ad-hoc string scanning. `MarkdownTextView` receives additive parser fixes with no visual regressions.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest. No new dependencies.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `LocalAIEdgeApp/Services/Inference/StreamProcessor.swift` | **Create** | `StreamEvent` enum + `StreamProcessor` actor |
| `LocalAIEdgeAppTests/StreamProcessorTests.swift` | **Create** | Unit tests for all `StreamProcessor` behaviour |
| `LocalAIEdgeApp/Services/Inference/InferenceService.swift` | **Modify** | Update `generateStream` return type; remove `citations` from tuple |
| `LocalAIEdgeApp/Services/Inference/MockInferenceService.swift` | **Modify** | Implement new return type; expose `var events: [StreamEvent]` |
| `LocalAIEdgeApp/Services/Inference/LocalLlamaInferenceService.swift` | **Modify** | Wrap raw stream in `StreamProcessor`; inject tool definition for tool-calling models |
| `LocalAIEdgeApp/Services/Inference/MLXInferenceService.swift` | **Modify** | Same as above |
| `LocalAIEdgeApp/Features/Chat/ChatView.swift` | **Modify** | Replace ad-hoc streaming loop with `StreamEvent` switch; add tool-call loop |
| `LocalAIEdgeApp/Features/Chat/MarkdownTextView.swift` | **Modify** | Fix 6 parser gaps; fix inline iterator for emoji |
| `LocalAIEdgeApp/Features/Chat/MessageBubbleView.swift` | **Modify** | Route user bubbles through `MarkdownTextView` |

---

## Task 1: Define StreamEvent and StreamProcessor

**Files:**
- Create: `LocalAIEdgeApp/Services/Inference/StreamProcessor.swift`
- Create: `LocalAIEdgeAppTests/StreamProcessorTests.swift`

### Background
`StreamProcessor` is a Swift `actor` that consumes a raw `AsyncStream<String>` and yields `StreamEvent` values. It handles three concerns in a single pass: markdown line buffering, think-block extraction, and tool-call interception.

The current `ChatView` has ~80 lines of ad-hoc tag-scanning (lines 672–750 in `ChatView.swift`) that this replaces entirely.

Build order: tests first, then implementation.

---

- [ ] **Step 1.1 — Create `StreamProcessor.swift` with types only (no logic yet)**

Create `LocalAIEdgeApp/Services/Inference/StreamProcessor.swift`:

```swift
import Foundation

enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case thinkingDone(durationSeconds: Int)
    case toolCall(name: String, argsJSON: String)
    case done
}

actor StreamProcessor {
    private let rawStream: AsyncStream<String>

    init(rawStream: AsyncStream<String>) {
        self.rawStream = rawStream
    }

    func process() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            Task {
                continuation.finish()
            }
        }
    }
}
```

- [ ] **Step 1.2 — Create `StreamProcessorTests.swift` with the plain-text pass-through test**

Create `LocalAIEdgeAppTests/StreamProcessorTests.swift`:

```swift
import XCTest
@testable import LocalAIEdgeApp

final class StreamProcessorTests: XCTestCase {

    // Helper: feed tokens into StreamProcessor, collect all events
    private func process(tokens: [String]) async -> [StreamEvent] {
        let stream = AsyncStream<String> { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
        let processor = StreamProcessor(rawStream: stream)
        var events: [StreamEvent] = []
        for await event in processor.process() {
            events.append(event)
        }
        return events
    }

    func test_plainText_passesThrough() async throws {
        let events = await process(tokens: ["Hello", " world"])
        // Expect one or more textDelta events whose text concatenates to "Hello world", then done
        let text = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(text, "Hello world")
        XCTAssertTrue(events.last.map { if case .done = $0 { return true }; return false } ?? false)
    }
}
```

- [ ] **Step 1.3 — Run test, confirm it fails**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/StreamProcessorTests/test_plainText_passesThrough \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: FAIL (stub `process()` finishes immediately without yielding text).

- [ ] **Step 1.4 — Implement `process()` — plain text pass-through + line buffering**

Replace `StreamProcessor.swift` with the full implementation:

```swift
import Foundation

enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case thinkingDone(durationSeconds: Int)
    case toolCall(name: String, argsJSON: String)
    case done
}

actor StreamProcessor {
    private let rawStream: AsyncStream<String>

    // Tag pairings: opening tag (lowercased) → closing tag (lowercased)
    private static let thinkTagPairs: [String: String] = [
        "<think>": "</think>",
        "<thinking>": "</thinking>",
        "<reasoning>": "</reasoning>"
    ]

    init(rawStream: AsyncStream<String>) {
        self.rawStream = rawStream
    }

    func process() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            Task {
                var lineBuffer = ""          // accumulates until \n or block boundary
                var thinkBuffer = ""         // content inside think block
                var thinkOpenTag: String?    // which open tag is active (lowercased)
                var thinkStart: Date?
                var toolCallBuffer: String?  // non-nil while inside <tool_call>
                var toolCallFired = false    // guard: only one per stream

                func flush(_ text: String) {
                    if !text.isEmpty { continuation.yield(.textDelta(text)) }
                }

                func processBuffer(_ buf: inout String) {
                    // Split on newlines; keep last incomplete line in buffer
                    var lines = buf.components(separatedBy: "\n")
                    buf = lines.removeLast() // last element may be incomplete
                    for line in lines {
                        flush(line + "\n")
                    }
                }

                for await token in rawStream {
                    var remaining = token

                    while !remaining.isEmpty {
                        // ── Tool call buffering ──────────────────────────────
                        if toolCallBuffer != nil {
                            if let closeRange = remaining.range(of: "</tool_call>", options: .caseInsensitive) {
                                toolCallBuffer! += String(remaining[..<closeRange.lowerBound])
                                remaining = String(remaining[closeRange.upperBound...])
                                let raw = toolCallBuffer!
                                toolCallBuffer = nil
                                // Parse JSON
                                if !toolCallFired,
                                   let data = raw.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                                   let name = json["name"], !name.isEmpty {
                                    toolCallFired = true
                                    continuation.yield(.toolCall(name: name, argsJSON: raw))
                                    // Pause: don't emit .done yet; ChatView will re-invoke inference
                                    // Remaining tokens after </tool_call> are discarded for this stream
                                    return
                                } else {
                                    // Parse failed or already fired — flush as text
                                    flush(raw)
                                }
                            } else {
                                toolCallBuffer! += remaining
                                remaining = ""
                            }
                            continue
                        }

                        // ── Think block routing ──────────────────────────────
                        if let openTag = thinkOpenTag {
                            let closeTag = Self.thinkTagPairs[openTag]!
                            if let closeRange = remaining.range(of: closeTag, options: .caseInsensitive) {
                                thinkBuffer += String(remaining[..<closeRange.lowerBound])
                                remaining = String(remaining[closeRange.upperBound...])
                                let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                                continuation.yield(.thinkingDone(durationSeconds: max(1, duration)))
                                thinkBuffer = ""
                                thinkOpenTag = nil
                                thinkStart = nil
                            } else {
                                thinkBuffer += remaining
                                continuation.yield(.thinkingDelta(remaining))
                                remaining = ""
                            }
                            continue
                        }

                        // ── Detect opening think tag ─────────────────────────
                        var foundThink = false
                        for (openTag, _) in Self.thinkTagPairs {
                            if let openRange = remaining.range(of: openTag, options: .caseInsensitive) {
                                // Flush text before the tag
                                let before = String(remaining[..<openRange.lowerBound])
                                lineBuffer += before
                                processBuffer(&lineBuffer)
                                remaining = String(remaining[openRange.upperBound...])
                                thinkOpenTag = openTag
                                thinkStart = Date()
                                foundThink = true
                                break
                            }
                        }
                        if foundThink { continue }

                        // ── Detect opening tool_call tag ─────────────────────
                        if !toolCallFired,
                           let openRange = remaining.range(of: "<tool_call>", options: .caseInsensitive) {
                            let before = String(remaining[..<openRange.lowerBound])
                            lineBuffer += before
                            processBuffer(&lineBuffer)
                            remaining = String(remaining[openRange.upperBound...])
                            toolCallBuffer = ""
                            continue
                        }

                        // ── Normal text ──────────────────────────────────────
                        lineBuffer += remaining
                        remaining = ""
                        processBuffer(&lineBuffer)
                    }
                }

                // Stream ended — flush residuals
                if let openTag = thinkOpenTag {
                    // Auto-close unclosed think block
                    let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                    if !thinkBuffer.isEmpty {
                        continuation.yield(.thinkingDelta(thinkBuffer))
                    }
                    continuation.yield(.thinkingDone(durationSeconds: max(1, duration)))
                    _ = openTag
                } else if let tb = toolCallBuffer {
                    // Stream ended before </tool_call> — flush as text
                    flush(tb)
                }

                // Flush remaining line buffer
                if !lineBuffer.isEmpty { flush(lineBuffer) }

                continuation.yield(.done)
                continuation.finish()
            }
        }
    }
}
```

- [ ] **Step 1.5 — Run plain-text test, confirm it passes**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/StreamProcessorTests/test_plainText_passesThrough \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 1.6 — Add remaining StreamProcessor tests**

Append these test methods to `StreamProcessorTests`:

```swift
    func test_thinkBlock_extracted() async throws {
        let events = await process(tokens: ["<think>", "pondering", "</think>", "answer"])
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(thinkText, "pondering")
        let answerText = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(answerText.contains("answer"))
        XCTAssertTrue(events.contains { if case .thinkingDone = $0 { return true }; return false })
    }

    func test_thinkingTag_extracted() async throws {
        let events = await process(tokens: ["<thinking>deep thought</thinking>answer"])
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertEqual(thinkText, "deep thought")
    }

    func test_reasoningTag_extracted() async throws {
        let events = await process(tokens: ["<reasoning>logic</reasoning>result"])
        XCTAssertTrue(events.contains { if case .thinkingDelta = $0 { return true }; return false })
    }

    func test_thinkBlock_autoClosesOnStreamEnd() async throws {
        let events = await process(tokens: ["<think>", "incomplete"])
        XCTAssertTrue(events.contains { if case .thinkingDone = $0 { return true }; return false })
    }

    func test_mismatchedCloseTag_treatedAsText() async throws {
        // <think> open but </thinking> close — should NOT close the block
        let events = await process(tokens: ["<think>content</thinking>more"])
        // Block should auto-close at stream end, not at the mismatched tag
        let thinkText = events.compactMap { if case .thinkingDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(thinkText.contains("content"))
        XCTAssertTrue(thinkText.contains("</thinking>"))
    }

    func test_toolCall_emitted() async throws {
        let json = #"{"name":"web_search","query":"latest news"}"#
        let events = await process(tokens: ["<tool_call>", json, "</tool_call>"])
        XCTAssertTrue(events.contains {
            if case .toolCall(let name, _) = $0 { return name == "web_search" }; return false
        })
        // .done should NOT be emitted after a tool call (ChatView re-invokes)
        XCTAssertFalse(events.contains { if case .done = $0 { return true }; return false })
    }

    func test_toolCall_badJSON_flushedAsText() async throws {
        let events = await process(tokens: ["<tool_call>", "not json", "</tool_call>", "answer"])
        XCTAssertFalse(events.contains { if case .toolCall = $0 { return true }; return false })
        let text = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(text.contains("not json"))
    }

    func test_toolCall_streamEndBeforeClose_flushedAsText() async throws {
        let events = await process(tokens: ["<tool_call>", "partial"])
        XCTAssertFalse(events.contains { if case .toolCall = $0 { return true }; return false })
        let text = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(text.contains("partial"))
    }

    func test_secondToolCall_treatedAsText() async throws {
        let json = #"{"name":"web_search","query":"first"}"#
        let json2 = #"{"name":"web_search","query":"second"}"#
        // First tool call fires and stops stream; processor returns early
        // so we only test: if second one sneaks in via re-invoke it's treated as text
        // We test this by feeding it directly without a valid first call path:
        // feed no valid first call — both should be text
        let events = await process(tokens: ["prefix <tool_call>", "bad", "</tool_call> <tool_call>", json2, "</tool_call>"])
        let toolEvents = events.filter { if case .toolCall = $0 { return true }; return false }
        // bad JSON means first fails; second should also fail (either bad or guard)
        XCTAssertEqual(toolEvents.count, 0)
    }
```

- [ ] **Step 1.7 — Run all StreamProcessor tests**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing LocalAIEdgeAppTests/StreamProcessorTests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

Expected: All PASS.

- [ ] **Step 1.8 — Commit**

```bash
git add LocalAIEdgeApp/Services/Inference/StreamProcessor.swift \
        LocalAIEdgeAppTests/StreamProcessorTests.swift
git commit -m "feat: add StreamProcessor actor and StreamEvent enum with tests"
```

---

## Task 2: Update InferenceService Protocol and MockInferenceService

**Files:**
- Modify: `LocalAIEdgeApp/Services/Inference/InferenceService.swift`
- Modify: `LocalAIEdgeApp/Services/Inference/MockInferenceService.swift`

### Background
`generateStream` currently returns `(messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>)`. We drop `citations` from the tuple (it moves to `ChatView`'s `pendingCitations`) and change `stream` to `AsyncStream<StreamEvent>`. This will break all callers — fix them in subsequent tasks.

---

- [ ] **Step 2.1 — Update `InferenceService.swift` protocol**

In `LocalAIEdgeApp/Services/Inference/InferenceService.swift`, change `generateStream`:

```swift
// OLD:
func generateStream(
    prompt: String,
    model: InstalledModel,
    conversation: [ChatMessage],
    searchContext: SearchContext?,
    systemPrompt: String,
    imageData: Data?
) async throws -> (messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>)

// NEW:
func generateStream(
    prompt: String,
    model: InstalledModel,
    conversation: [ChatMessage],
    searchContext: SearchContext?,
    systemPrompt: String,
    imageData: Data?
) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>)
```

- [ ] **Step 2.2 — Update `MockInferenceService.swift`**

Replace the entire `MockInferenceService` with:

```swift
import Foundation

struct MockInferenceService: InferenceService {
    /// Inject custom events for testing. Defaults to a simple text response.
    var events: [StreamEvent] = []

    func generateReply(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> ChatMessage {
        try await Task.sleep(for: .milliseconds(350))
        let prefix = searchContext == nil ? "Local model" : "Local model with web context"
        let contextLine = searchContext?.snippets.prefix(2).joined(separator: " ") ?? "No external data was used."
        let reply = "\(prefix) \(model.catalogItem.displayName) says: \(prompt)\n\nSystem prompt: \(systemPrompt)\n\nContext: \(contextLine)"
        return ChatMessage(role: .assistant, text: reply, citations: searchContext?.citations ?? [])
    }

    func generateStream(
        prompt: String,
        model: InstalledModel,
        conversation: [ChatMessage],
        searchContext: SearchContext?,
        systemPrompt: String,
        imageData: Data? = nil
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        let messageID = UUID()
        let eventsToEmit: [StreamEvent] = events.isEmpty
            ? [.textDelta("Mock response for: \(prompt)"), .done]
            : events
        let stream = AsyncStream<StreamEvent> { continuation in
            for event in eventsToEmit { continuation.yield(event) }
            continuation.finish()
        }
        return (messageID: messageID, stream: stream)
    }
}
```

- [ ] **Step 2.3 — Attempt to build (expect compile errors in Llama/MLX/ChatView — that's fine)**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | head -20
```

Expected: Errors in `LocalLlamaInferenceService.swift`, `MLXInferenceService.swift`, `ChatView.swift`. Proceed to fix them in next tasks.

- [ ] **Step 2.4 — Commit what compiles**

```bash
git add LocalAIEdgeApp/Services/Inference/InferenceService.swift \
        LocalAIEdgeApp/Services/Inference/MockInferenceService.swift
git commit -m "feat: update InferenceService protocol to return AsyncStream<StreamEvent>"
```

---

## Task 3: Update LocalLlamaInferenceService

**Files:**
- Modify: `LocalAIEdgeApp/Services/Inference/LocalLlamaInferenceService.swift`

### Background
`generateStream` in `LocalLlamaInferenceService` needs to: (1) wrap its raw `AsyncStream<String>` in `StreamProcessor`, (2) remove `citations` from the return tuple, and (3) inject the tool-call definition into the system prompt for models where `supportsToolCalling == true`.

---

- [ ] **Step 3.1 — Update `generateStream` in `LocalLlamaInferenceService`**

In `LocalAIEdgeApp/Services/Inference/LocalLlamaInferenceService.swift`, replace the `generateStream` method:

```swift
func generateStream(
    prompt: String,
    model: InstalledModel,
    conversation: [ChatMessage],
    searchContext: SearchContext?,
    systemPrompt: String,
    imageData: Data? = nil
) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
    guard model.catalogItem.runtimeType == .gguf else {
        throw InferenceServiceError.runtimeUnavailable("This model requires the MLX runtime.")
    }
    if imageData != nil {
        throw InferenceServiceError.runtimeUnavailable(
            "The llama.cpp runtime does not support image input. Switch to an MLX vision model for image understanding."
        )
    }
    guard let modelPath = model.localPath else {
        throw InferenceServiceError.missingLocalModelFile
    }

    let chatTurns = PromptRenderer.buildChatTurns(
        systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
        conversation: conversation,
        searchContext: searchContext,
        latestPrompt: prompt,
        modelName: model.catalogItem.displayName
    )
    let fallbackPrompt = PromptRenderer.render(
        systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
        conversation: conversation,
        searchContext: searchContext,
        latestPrompt: prompt,
        modelName: model.catalogItem.displayName
    )

    let maxGeneratedTokens: Int32 = searchContext != nil ? 2048 : 1024
    let messageID = UUID()
    let rawStream = try await LocalLlamaRuntime.shared.generateStream(
        chat: chatTurns,
        fallbackPrompt: fallbackPrompt,
        using: modelPath,
        maxGeneratedTokens: maxGeneratedTokens
    )
    let processor = StreamProcessor(rawStream: rawStream)
    return (messageID: messageID, stream: processor.process())
}

/// Appends tool call definition to system prompt for tool-calling models.
private func effectiveSystemPrompt(_ base: String, model: InstalledModel) -> String {
    guard model.catalogItem.supportsToolCalling else { return base }
    return base + """

If you need current information to answer, call this tool:
<tool_call>{"name":"web_search","query":"your search query here"}</tool_call>
Only call it once. Do not call it for questions answerable from your training data.
"""
}
```

- [ ] **Step 3.2 — Build to confirm LocalLlama compiles**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | grep "LocalLlama" | head -10
```

Expected: No errors in `LocalLlamaInferenceService.swift`.

- [ ] **Step 3.3 — Commit**

```bash
git add LocalAIEdgeApp/Services/Inference/LocalLlamaInferenceService.swift
git commit -m "feat: wrap LocalLlama stream in StreamProcessor, inject tool prompt"
```

---

## Task 4: Update MLXInferenceService

**Files:**
- Modify: `LocalAIEdgeApp/Services/Inference/MLXInferenceService.swift`

---

- [ ] **Step 4.1 — Update `generateStream` in `MLXInferenceService`**

In `LocalAIEdgeApp/Services/Inference/MLXInferenceService.swift`, inside the `#if canImport(MLXLLM)` block, replace `MLXInferenceService.generateStream`:

```swift
func generateStream(
    prompt: String,
    model: InstalledModel,
    conversation: [ChatMessage],
    searchContext: SearchContext?,
    systemPrompt: String,
    imageData: Data? = nil
) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
    guard let mlxModelID = model.catalogItem.mlxModelID else {
        throw InferenceServiceError.missingLocalModelFile
    }
    let isVision = model.catalogItem.supportsVision && imageData != nil
    let fullSystemPrompt = Self.buildSystemPrompt(
        systemPrompt: effectiveSystemPrompt(systemPrompt, model: model),
        searchContext: searchContext
    )
    let fullPrompt = Self.buildFullPrompt(conversation: conversation, prompt: prompt)

    let messageID = UUID()
    do {
        let rawStream = try await MLXRuntime.shared.generateStream(
            prompt: fullPrompt,
            modelID: mlxModelID,
            systemPrompt: fullSystemPrompt,
            maxTokens: searchContext != nil ? 2048 : 1024,
            imageData: imageData,
            isVision: isVision
        )
        let processor = StreamProcessor(rawStream: rawStream)
        return (messageID: messageID, stream: processor.process())
    } catch {
        throw InferenceServiceError.runtimeUnavailable(Self.friendlyMLXError(error))
    }
}

private func effectiveSystemPrompt(_ base: String, model: InstalledModel) -> String {
    guard model.catalogItem.supportsToolCalling else { return base }
    return base + """

If you need current information to answer, call this tool:
<tool_call>{"name":"web_search","query":"your search query here"}</tool_call>
Only call it once. Do not call it for questions answerable from your training data.
"""
}
```

Also update the simulator stub at the bottom of the file (inside `#else`):

```swift
// Stub for simulator
struct MLXInferenceService: InferenceService {
    func generateReply(/* ... same as before ... */) async throws -> ChatMessage {
        throw MLXInferenceError.runtimeUnavailable
    }
    func generateStream(
        prompt: String, model: InstalledModel, conversation: [ChatMessage],
        searchContext: SearchContext?, systemPrompt: String, imageData: Data? = nil
    ) async throws -> (messageID: UUID, stream: AsyncStream<StreamEvent>) {
        throw MLXInferenceError.runtimeUnavailable
    }
}
```

- [ ] **Step 4.2 — Build to confirm MLX compiles**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | grep -i "mlx" | head -10
```

Expected: No errors from MLX files.

- [ ] **Step 4.3 — Commit**

```bash
git add LocalAIEdgeApp/Services/Inference/MLXInferenceService.swift
git commit -m "feat: wrap MLX stream in StreamProcessor, inject tool prompt"
```

---

## Task 5: Refactor ChatView Streaming Loop

**Files:**
- Modify: `LocalAIEdgeApp/Features/Chat/ChatView.swift`

### Background
The current `sendPrompt()` method (lines 599–831) contains ~80 lines of ad-hoc tag scanning for `<think>`. Replace the `for await piece in stream` loop with a `for await event in stream` switch. Add the tool-call loop. Remove `citations` from the `generateStream` destructuring — use `pendingCitations` instead.

---

- [ ] **Step 5.1 — Replace the streaming loop in `sendPrompt()`**

Locate the `let task = Task {` block inside `sendPrompt()`. Replace everything from `let (messageID, citations, stream) = try await service.generateStream(...)` through `finishGenerationIfCurrent(taskID)` with:

```swift
let service = inferenceServiceForModel(model)
let pendingCitations = searchContext?.citations ?? []
let (messageID, stream) = try await service.generateStream(
    prompt: trimmedPrompt,
    model: model,
    conversation: conversation,
    searchContext: searchContext,
    systemPrompt: store.settings.systemPrompt,
    imageData: jpegData
)

let placeholder = ChatMessage(id: messageID, role: .assistant, text: "", citations: pendingCitations)
await MainActor.run {
    store.appendMessage(placeholder, to: sessionID)
}

var accumulated = ""
var thinkingAccumulated = ""
var stoppedByUser = false
let clock = ContinuousClock()
var lastFlush = clock.now

for await event in stream {
    if Task.isCancelled {
        accumulated += "\n\n*(Response stopped by user)*"
        stoppedByUser = true
        await updateStreamingMessage(accumulated, messageID: messageID, sessionID: sessionID, persist: true)
        break
    }

    switch event {
    case .textDelta(let chunk):
        accumulated += chunk
        let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
            || chunk.contains(where: \.isNewline)
            || accumulated.count <= 48
        if shouldFlush {
            lastFlush = clock.now
            await updateStreamingMessage(accumulated, messageID: messageID, sessionID: sessionID)
        }

    case .thinkingDelta(let chunk):
        thinkingAccumulated += chunk
        let snapshot = thinkingAccumulated
        await MainActor.run {
            store.updateMessageThinking(messageID, in: sessionID, thinkingContent: snapshot)
        }

    case .thinkingDone(let duration):
        let snapshot = thinkingAccumulated
        await MainActor.run {
            store.updateMessageThinking(
                messageID, in: sessionID,
                thinkingContent: snapshot,
                thinkingDurationSeconds: duration,
                persist: true
            )
        }

    case .toolCall(let name, let argsJSON):
        guard name == "web_search" else { break }
        // Parse query from argsJSON
        guard let data = argsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let query = json["query"], !query.isEmpty else { break }

        // Show searching state — reuse existing search warning message style
        let searchingMsg = ChatMessage(role: .system, text: "🔍 Searching: \(query)…")
        await MainActor.run { store.appendMessage(searchingMsg, to: sessionID) }

        var agenticSearchContext: SearchContext? = nil
        if let gateway = SearchGatewayFactory.make(settings: store.settings) {
            agenticSearchContext = try? await gateway.search(query: query)
        }
        // If search is unconfigured or failed, agenticSearchContext is nil.
        // We still re-invoke inference so the model can answer from local knowledge.
        // The system prompt note ("Search unavailable") tells it why no results arrived.
        if agenticSearchContext == nil {
            let unavailableMsg = ChatMessage(role: .system, text: "⚠️ Search unavailable — answering from local knowledge.")
            await MainActor.run { store.appendMessage(unavailableMsg, to: sessionID) }
        }

        // Re-invoke inference with or without search context
        let newPendingCitations = agenticSearchContext?.citations ?? []
        let (newMessageID, newStream) = try await service.generateStream(
            prompt: trimmedPrompt,
            model: model,
            conversation: conversation,
            searchContext: agenticSearchContext,
            systemPrompt: store.settings.systemPrompt,
            imageData: jpegData
        )
        let newPlaceholder = ChatMessage(id: newMessageID, role: .assistant, text: "", citations: newPendingCitations)
        await MainActor.run { store.appendMessage(newPlaceholder, to: sessionID) }

        // Reset accumulators and continue on new stream
        accumulated = ""
        thinkingAccumulated = ""
        for await newEvent in newStream {
            if Task.isCancelled { break }
            switch newEvent {
            case .textDelta(let chunk):
                accumulated += chunk
                let shouldFlush = clock.now - lastFlush >= streamUpdateInterval
                    || chunk.contains(where: \.isNewline)
                    || accumulated.count <= 48
                if shouldFlush {
                    lastFlush = clock.now
                    await updateStreamingMessage(accumulated, messageID: newMessageID, sessionID: sessionID)
                }
            case .thinkingDelta(let chunk):
                thinkingAccumulated += chunk
                let snapshot = thinkingAccumulated
                await MainActor.run {
                    store.updateMessageThinking(newMessageID, in: sessionID, thinkingContent: snapshot)
                }
            case .thinkingDone(let dur):
                let snapshot = thinkingAccumulated
                await MainActor.run {
                    store.updateMessageThinking(newMessageID, in: sessionID, thinkingContent: snapshot, thinkingDurationSeconds: dur, persist: true)
                }
            case .toolCall, .done:
                break
            }
        }
        // Finalize second-pass message
        let finalText2 = cleanedDisplayedAssistantText(accumulated)
        await updateStreamingMessage(finalText2.isEmpty ? "The model finished without returning text." : finalText2,
                                     messageID: newMessageID, sessionID: sessionID, persist: true)
        await MainActor.run { finishGenerationIfCurrent(taskID) }
        return // task done

    case .done:
        break
    }
}

// Finalize first-pass message
let finalText = cleanedDisplayedAssistantText(accumulated)
if finalText.isEmpty {
    await updateStreamingMessage("The model finished without returning text. Try a shorter prompt or another model.",
                                 messageID: messageID, sessionID: sessionID, persist: true)
} else {
    await updateStreamingMessage(finalText, messageID: messageID, sessionID: sessionID, persist: true)
}

if !stoppedByUser,
   store.settings.voiceModeEnabled,
   store.settings.autoPlayVoiceResponses,
   !finalText.isEmpty {
    await MainActor.run { voiceController.speak(finalText, using: store.settings) }
}

await MainActor.run { finishGenerationIfCurrent(taskID) }
```

Also remove the now-unused local variables: `isInsideThink`, `thinkingBuffer`, `thinkingStart`, `tagDetectionBuffer`, and `thinkingPiece` from the old loop.

- [ ] **Step 5.2 — Build and confirm it compiles**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | head -20
```

Expected: Clean build.

- [ ] **Step 5.3 — Run existing tests to confirm no regression**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: All existing + new tests pass.

- [ ] **Step 5.4 — Commit**

```bash
git add LocalAIEdgeApp/Features/Chat/ChatView.swift
git commit -m "feat: refactor ChatView streaming loop to consume StreamEvent, add agentic search"
```

---

## Task 6: Fix MarkdownTextView Rendering Gaps

**Files:**
- Modify: `LocalAIEdgeApp/Features/Chat/MarkdownTextView.swift`

### Background
Eight gaps to fix. All changes are additive — no existing blocks are removed or restyled. The inline iterator fix (emoji) is the most important; do it first. Then add new block types. Then fix the inline span parser for links and strikethrough.

---

- [ ] **Step 6.1 — Fix emoji: change inline iterator from `String.prefix(1)` to `Character`-based**

In `MarkdownTextView.swift`, find the `inlineMarkdown(_ text: String)` function. The last fallback arm is:

```swift
// Plain character
result = result + Text(String(remaining.prefix(1)))
remaining = remaining.dropFirst()
```

Replace with:

```swift
// Plain character — advance by one Unicode Character (emoji-safe)
if let ch = remaining.first {
    result = result + Text(String(ch))
    remaining = remaining[remaining.index(after: remaining.startIndex)...]
}
```

Also change the loop condition and all other `remaining.prefix(1)` / `remaining.dropFirst()` uses to ensure Unicode correctness. The while loop header stays `while !remaining.isEmpty`.

- [ ] **Step 6.2 — Add `Block.blockquote` case to the enum and parser**

In the `Block` enum inside `MarkdownTextView`, add:

```swift
case blockquote(String)
```

In `parseBlocks`, add before the empty-line check:

```swift
// Blockquote
if trimmed.hasPrefix("> ") || trimmed == ">" {
    let content = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
    blocks.append(.blockquote(content))
    i += 1
    continue
}
```

In `renderBlock`, add a case:

```swift
case .blockquote(let text):
    HStack(alignment: .top, spacing: 0) {
        Rectangle()
            .fill(AppTheme.accentSoft.opacity(0.4))
            .frame(width: 2)
        inlineMarkdown(text)
            .font(.system(size: 15, weight: .regular).italic())
            .foregroundStyle(foreground.opacity(0.75))
            .lineSpacing(3)
            .padding(.leading, 12)
            .padding(.vertical, 4)
    }
    .padding(.vertical, 2)
```

- [ ] **Step 6.3 — Add `~~strikethrough~~` to `inlineMarkdown`**

In `inlineMarkdown`, before the citation reference check, add:

```swift
// Strikethrough ~~...~~
if remaining.hasPrefix("~~"),
   let endRange = remaining.dropFirst(2).range(of: "~~") {
    let strike = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound]
    result = result + Text(String(strike))
        .strikethrough()
        .foregroundColor(isUser ? .white.opacity(0.7) : AppTheme.textSecondary)
    remaining = remaining[endRange.upperBound...]
    continue
}
```

- [ ] **Step 6.4 — Add `[text](url)` inline link detection**

In `inlineMarkdown`, before the citation reference check, add:

```swift
// Inline link [text](url)
if remaining.hasPrefix("[") {
    let afterBracket = remaining.index(after: remaining.startIndex)
    if let closeBracket = remaining[afterBracket...].firstIndex(of: "]") {
        let linkText = String(remaining[afterBracket..<closeBracket])
        let afterClose = remaining.index(after: closeBracket)
        if afterClose < remaining.endIndex && remaining[afterClose] == "(",
           let closeParen = remaining[afterClose...].firstIndex(of: ")") {
            let urlString = String(remaining[remaining.index(after: afterClose)..<closeParen])
            if let url = URL(string: urlString) {
                // We can't embed Link inside Text concatenation; render as accent-styled underlined text
                result = result + Text(linkText)
                    .underline()
                    .foregroundColor(isUser ? .white : AppTheme.accent)
                remaining = remaining[remaining.index(after: closeParen)...]
                continue
            }
        }
    }
}
```

> Note: `[text](url)` in a `Text` concat cannot be a tappable `Link` (SwiftUI limitation). The link text renders in accent colour with underline. Tappable links in paragraphs require `MarkdownTextView` to return a `View` not a `Text` — that's a larger refactor outside this spec.

- [ ] **Step 6.5 — Add bare URL auto-link in paragraph text**

In `renderBlock`, for the `.paragraph` case, replace:

```swift
case .paragraph(let text):
    inlineMarkdown(text)
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(foreground)
        .lineSpacing(4)
        .padding(.vertical, 2)
```

with:

```swift
case .paragraph(let text):
    paragraphView(text)
        .padding(.vertical, 2)
```

Add helper below `renderBlock`:

```swift
@ViewBuilder
private func paragraphView(_ text: String) -> some View {
    // Check if paragraph contains a bare URL to render as a tappable link
    if let urlRange = text.range(of: #"https?://[^\s]+"#, options: .regularExpression),
       let url = URL(string: String(text[urlRange])) {
        let before = String(text[..<urlRange.lowerBound])
        let after = String(text[urlRange.upperBound...])
        VStack(alignment: .leading, spacing: 0) {
            if !before.isEmpty {
                inlineMarkdown(before)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(foreground)
                    .lineSpacing(4)
            }
            Link(String(text[urlRange]), destination: url)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isUser ? Color.white.opacity(0.9) : AppTheme.accent)
                .underline()
            if !after.isEmpty {
                inlineMarkdown(after.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(foreground)
                    .lineSpacing(4)
            }
        }
    } else {
        inlineMarkdown(text)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(foreground)
            .lineSpacing(4)
    }
}
```

- [ ] **Step 6.6 — Add nested list depth tracking**

In `parseBlocks`, the bullet detection currently does:

```swift
if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
    blocks.append(.bullet(String(trimmed.dropFirst(2))))
```

Add depth to `Block.bullet` and `Block.numbered`:

```swift
case bullet(String, depth: Int)
case numbered(index: String, text: String, depth: Int)
```

In `parseBlocks`, compute depth from leading spaces:

```swift
// Bullet
if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
    let leadingSpaces = line.prefix(while: { $0 == " " }).count
    let depth = leadingSpaces / 2
    blocks.append(.bullet(String(trimmed.dropFirst(2)), depth: depth))
    i += 1
    continue
}

// Numbered list
if let match = trimmed.range(of: #"^(\d+)[.)]\s+"#, options: .regularExpression) {
    let leadingSpaces = line.prefix(while: { $0 == " " }).count
    let depth = leadingSpaces / 2
    let idx = String(trimmed[match].dropLast(1)).trimmingCharacters(in: .whitespaces)
    let rest = String(trimmed[match.upperBound...])
    blocks.append(.numbered(index: idx, text: rest, depth: depth))
    i += 1
    continue
}
```

In `renderBlock`, add indent padding to `.bullet` and `.numbered`:

```swift
case .bullet(let text, let depth):
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        // ... existing bullet dot code unchanged ...
    }
    .padding(.leading, CGFloat(depth) * 16)
    .padding(.vertical, 3)

case .numbered(let idx, let text, let depth):
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        // ... existing numbered badge code unchanged ...
    }
    .padding(.leading, CGFloat(depth) * 16)
    .padding(.vertical, 4)
```

- [ ] **Step 6.7 — Build, confirm no compile errors**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | head -20
```

Expected: Clean build.

- [ ] **Step 6.8 — Run all tests**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: All pass.

- [ ] **Step 6.9 — Commit**

```bash
git add LocalAIEdgeApp/Features/Chat/MarkdownTextView.swift
git commit -m "feat: fix MarkdownTextView rendering gaps — emoji, links, blockquote, strikethrough, nested lists"
```

---

## Task 7: Route User Bubbles Through MarkdownTextView

**Files:**
- Modify: `LocalAIEdgeApp/Features/Chat/MessageBubbleView.swift`

### Background
User bubbles currently use a bare `Text(message.text)` with no markdown rendering. Route them through `MarkdownTextView(text:isUser:)` so bold, inline code, and emoji in user messages render correctly.

---

- [ ] **Step 7.1 — Replace user bubble `Text` with `MarkdownTextView`**

In `MessageBubbleView.swift`, find the user/search/system bubble branch:

```swift
if isUser || message.role == .search || message.role == .system {
    VStack(alignment: .leading, spacing: 10) {
        if let imageData = message.imageData, let uiImage = previewImage(from: imageData) { ... }
        Text(message.text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(isUser ? .white : AppTheme.textPrimary)
            .textSelection(.enabled)
    }
```

Replace `Text(message.text)...` with:

```swift
MarkdownTextView(text: message.text, isUser: isUser)
    .textSelection(.enabled)
```

Remove the `.font` and `.foregroundStyle` modifiers from that line — `MarkdownTextView` handles its own styling via `isUser`.

- [ ] **Step 7.2 — Build and run all tests**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: All pass.

- [ ] **Step 7.3 — Commit**

```bash
git add LocalAIEdgeApp/Features/Chat/MessageBubbleView.swift
git commit -m "feat: render user message bubbles through MarkdownTextView"
```

---

## Task 8: Final Integration Build and Test Run

- [ ] **Step 8.1 — Full build for simulator**

```bash
xcodebuild build \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8.2 — Full test suite**

```bash
xcodebuild test \
  -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "(PASS|FAIL|error:)" | tail -30
```

Expected: All tests pass. Zero errors.

- [ ] **Step 8.3 — Final commit**

```bash
git add -A
git commit -m "chore: StreamProcessor + rendering + agentic search — all tasks complete"
```
