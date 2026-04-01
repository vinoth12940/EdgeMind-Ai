# Stream Processor, Rendering Fixes & Agentic Search — Design Spec

**Date:** 2026-04-01
**Status:** Approved

---

## Problem Statement

Three related issues degrade the chat experience:

1. **Rendering gaps** — The custom `MarkdownTextView` parser is missing emoji handling, inline links, bare URLs, blockquotes, strikethrough, and nested lists. User message bubbles use a bare `Text()` with no markdown at all. During streaming, the parser runs on every partial token, causing raw syntax characters to flash mid-stream.

2. **Thinking fragility** — The `<think>` block extractor is implemented ad-hoc inside `ChatView`'s streaming loop. It only handles the exact `<think>` tag and would silently break for `<thinking>` or `<reasoning>` variants used by future models.

3. **Manual search only** — Web search is a user-controlled per-message toggle. Tool-calling models should be able to decide when to search autonomously based on the question.

---

## Scope

In scope:
- New `StreamProcessor` actor as a unified token processing layer
- `MarkdownTextView` rendering gap fixes (8 items)
- Reliable thinking block extraction across all model token formats
- Agentic tool-call search loop for `supportsToolCalling: true` models

Out of scope:
- Replacing `MarkdownTextView` with `AttributedString` (visual parity would be lost)
- Multiple tool calls per message (search once per inference run)
- Tool types other than `web_search`
- Changes to voice, model download, or auth flows

---

## Architecture: Unified Stream Processor

### Core Idea

A new `StreamProcessor` actor sits between the raw `AsyncStream<String>` from the inference runtimes and `ChatView`. Every token passes through it. It emits structured `StreamEvent` values that `ChatView` consumes as a simple switch.

### StreamEvent Enum

```swift
enum StreamEvent {
    case textDelta(String)                         // safe-to-render markdown chunk
    case thinkingDelta(String)                     // content inside a think block
    case thinkingDone(durationSeconds: Int)        // think block closed
    case toolCall(name: String, argsJSON: String)  // tool invocation intercepted (fires at most once per stream)
    case done                                      // stream finished
}
```

### Processing Rules

**Markdown buffering:**
- Accumulate tokens until a complete line boundary (`\n`) or a complete block delimiter (` ``` `, table row end, heading line end).
- Hold any incomplete inline span opener (`**`, `*`, `` ` ``, `~~`, `[`) in a buffer; do not emit until the span closes or a newline forces a flush.
- Emit `.textDelta` with complete, parseable chunks only.

**Thinking extraction:**
- On receiving an opening tag, enter thinking mode and record a start timestamp. Explicit tag pairings:
  - `<think>` → closes with `</think>`
  - `<thinking>` → closes with `</thinking>`
  - `<reasoning>` → closes with `</reasoning>`
- All tags matched case-insensitively. A mismatched closing tag (e.g. `</thinking>` while open with `<think>`) is treated as plain text, not a close signal.
- While in thinking mode, emit tokens as `.thinkingDelta` instead of `.textDelta`.
- On receiving the exact matching closing tag, emit `.thinkingDone(durationSeconds)` and return to normal mode.
- If the stream ends while still in thinking mode, emit `.thinkingDone(durationSeconds)` implicitly — do not leave the block open.
- Think block content is never included in the answer text.

**Tool call detection:**
- `StreamProcessor` tracks whether a `.toolCall` has already been emitted for the current stream. Only the **first** `<tool_call>` block is processed as a tool call. Any subsequent `<tool_call>` tags in the same stream are passed through as plain `.textDelta` to prevent infinite loops.
- On receiving the first `<tool_call>`, buffer all subsequent tokens until `</tool_call>`.
- If the stream ends before `</tool_call>` is received, flush the buffered content as `.textDelta` — do not emit a partial tool call.
- Parse the buffered content as JSON: `{"name": "web_search", "query": "…"}`.
- Emit `.toolCall(name:argsJSON:)` and pause — do not emit `.done` yet.
- If JSON parse fails or name is unrecognised, flush the buffered content as `.textDelta` and continue.

### Interface Change

`InferenceService.generateStream` return type changes from:

```swift
(messageID: UUID, citations: [SearchCitation], stream: AsyncStream<String>)
```

to:

```swift
(messageID: UUID, stream: AsyncStream<StreamEvent>)
```

**Citations:** The `citations: [SearchCitation]` field is removed from the return tuple. `StreamProcessor` only sees raw tokens and has no knowledge of `SearchContext` — citations never flow through `StreamEvent`. Instead, `ChatView` holds a local `var pendingCitations: [SearchCitation]` that it populates directly from `SearchContext.citations` before invoking `generateStream` (both for the manual-toggle path and after the agentic tool-call search returns). When `ChatView` calls `store.appendMessage` to commit the final assistant message, it passes `pendingCitations` as the `citations:` argument. `AppStateStore.appendMessage` remains the only write point for citations on a session.

`LocalLlamaInferenceService` and `MLXInferenceService` both wrap their existing raw token stream in `StreamProcessor` before returning. `MockInferenceService` gets a stub that can emit configurable sequences of `StreamEvent` for testing `ChatView`'s tool-call loop and thinking display.

---

## Section 2: MarkdownTextView Rendering Fixes

All fixes are additive — no existing block types are removed or restyled.

### Parser Fixes

| Gap | Fix |
|---|---|
| Emoji garbling | Iterate `inlineMarkdown()` by `Character` (Unicode scalar-aware) instead of `String.prefix(1)` |
| `[text](url)` inline links | Detect `[…](…)` pattern in inline parser; render as accent-coloured tappable `Link` view |
| Bare `https://` URLs | Detect `https?://[^\s]+` in paragraph text; auto-wrap in `Link` |
| `> blockquote` | New `Block.blockquote(String)` case; render with left accent bar (2pt, `AppTheme.accentSoft.opacity(0.4)`), indented, italic foreground |
| `~~strikethrough~~` | Detect `~~…~~` in inline parser; apply `.strikethrough()` modifier |
| Nested lists | Track leading-space count; render nested `.bullet` / `.numbered` with `padding(.leading, CGFloat(depth) * 16)` |
| Partial tokens during streaming | Handled upstream by `StreamProcessor` — parser always receives complete lines |
| User message bubbles | Route `MessageBubbleView` user messages through `MarkdownTextView(text:isUser:)` instead of bare `Text()` |

### What Does Not Change

All current visual styling is preserved: gradient bullet dots, numbered circle badges, accent-coloured headings with underlines, code block language headers, dark alternating table rows, `AppTheme` colours throughout.

---

## Section 3: Thinking Reliability & Agentic Search

### Thinking

`StreamProcessor` replaces the ad-hoc `<think>` scanning in `ChatView`. The recognized opening tags are: `<think>`, `<thinking>`, `<reasoning>` (matched case-insensitively). Each maps to its corresponding closing tag.

`ChatView` handles `.thinkingDelta` by calling `store.updateMessageThinking(_:in:thinkingContent:)` and `.thinkingDone` by calling `store.updateMessageThinking(_:in:thinkingContent:thinkingDurationSeconds:persist:)` — same calls as today, just triggered by events instead of inline string scanning.

`ThinkingDisclosureRow` UI is unchanged. Collapsed by default, shows "Thought for Xs" pill when done.

### Agentic Tool-Call Search

**Eligibility:** Only models with `catalogItem.supportsToolCalling == true` participate. All other models use the existing manual toggle path with zero changes.

**System prompt injection** (in `LocalLlamaInferenceService.buildChatTurns` and `MLXInferenceService.buildSystemPrompt`). For MLX models without a chat template, the tool definition is appended to the fallback plain-text system section using the same `buildFullPrompt` concatenation path — tool-calling models in the catalog are expected to have a chat template, but the injection applies regardless:

```
If you need current information to answer, call this tool:
<tool_call>{"name":"web_search","query":"your search query here"}</tool_call>
Only call it once. Do not call it for questions answerable from your training data.
```

**ChatView tool call loop:**

```
receive .toolCall("web_search", argsJSON)
  → parse query from argsJSON
  → set isSending = true, show SearchDisclosureRow "Searching…" state
  → call SearchGateway.search(query)
  → on success: build SearchContext with results
  → re-invoke inferenceService.generateStream(..., searchContext: searchContext)
  → continue normal streaming loop
  → on failure / no gateway configured: inject tool_result "Search unavailable", re-invoke without SearchContext
```

**Manual toggle compatibility:** The `liveSearchEnabled` toggle in `ChatComposerView` continues to work as before for all models. For tool-calling models, a manual toggle forces search before inference even starts (existing behaviour). The agentic path only activates when the toggle is off and the model itself decides to call the tool.

---

## Files Changed

| File | Change |
|---|---|
| `Services/Inference/StreamProcessor.swift` | **New** — StreamProcessor actor, StreamEvent enum |
| `Services/Inference/InferenceService.swift` | Update `generateStream` return type to `AsyncStream<StreamEvent>` |
| `Services/Inference/LocalLlamaInferenceService.swift` | Wrap raw stream in StreamProcessor; inject tool definition into system prompt for tool-calling models |
| `Services/Inference/MLXInferenceService.swift` | Same as above |
| `Services/Inference/MockInferenceService.swift` | Update stub to match new return type |
| `Features/Chat/ChatView.swift` | Consume `StreamEvent` switch; add tool call loop |
| `Features/Chat/MarkdownTextView.swift` | Add 6 rendering fixes; fix inline iterator |
| `Features/Chat/MessageBubbleView.swift` | Route user bubbles through `MarkdownTextView` |

---

## Testing

- `PromptRendererTests.swift` — no changes needed (PromptRenderer is unaffected)
- `DeviceCapabilityTests.swift` — no changes needed
- New: `StreamProcessorTests.swift` — unit tests for each StreamEvent type:
  - Partial inline span buffering (emits only on close; newline forces flush)
  - Think block open/close (`<think>`, `<thinking>`, `<reasoning>`)
  - Think block auto-close on stream end
  - Mismatched think tag treated as plain text
  - Tool call JSON parse success → `.toolCall` emitted
  - Tool call JSON parse failure → content flushed as `.textDelta`
  - Stream-end before `</tool_call>` → buffered content flushed as `.textDelta`
  - Second `<tool_call>` in same stream treated as plain text (loop guard)
  - Pass-through for plain text (no regressions)
- `MockInferenceService` exposes `var events: [StreamEvent]` so callers can inject sequences for unit-testing `ChatView`'s tool-call loop and thinking update paths
