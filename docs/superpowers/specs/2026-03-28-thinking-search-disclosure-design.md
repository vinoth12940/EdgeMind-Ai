# Thinking & Search Disclosure UI — Design Spec

**Date:** 2026-03-28
**Status:** Approved → Implementation

---

## Problem

1. `<think>...</think>` tokens from thinking models (Qwen 3) are stripped entirely by `AssistantResponseSanitizer`. Users never see the reasoning chain.
2. Search results appear as a separate `.search` role bubble prepended before the assistant reply. If inference is cancelled, the search bubble is orphaned with no response beneath it.

---

## Solution

Inline disclosure rows inside the assistant bubble:

- **Thinking row** — purple accent, collapsed by default, only shown when `message.thinkingContent != nil` (thinking models only, gated by `isThinkingModel`). Tokens stream live into the expanded view if user taps during streaming.
- **Search row** — teal accent, collapsed by default, shown whenever `message.citations` is non-empty (all models with search enabled). Expands to a source list; each source is a `Link` that opens Safari.

---

## Data Model Changes — `ChatMessage.swift`

Add two mutable fields:

```swift
var thinkingContent: String?        // thinking buffer; updated token-by-token during streaming
var thinkingDurationSeconds: Int?   // set when </think> closes; nil while still thinking
```

Derived display state (no stored flag needed):
- `thinkingContent != nil && thinkingDurationSeconds == nil` → "Thinking…" (animated dots)
- `thinkingDurationSeconds != nil` → "Thought for Xs" (collapsed row)

---

## Streaming Loop Changes — `ChatView.sendMessage()`

Track locally:
```swift
var isInsideThink = false
var thinkingStart: Date? = nil
```

Per token:
- Token contains `<think>` → set `isInsideThink = true`, record `thinkingStart`, initialise `message.thinkingContent = ""`
- `isInsideThink == true` → append token (stripped of tag) to `message.thinkingContent`
- Token contains `</think>` → set `isInsideThink = false`, compute duration and set `message.thinkingDurationSeconds`
- Otherwise → append to `message.text` as today

**Remove** the three lines that prepend a `.search` role `ChatMessage` before the assistant placeholder.

---

## Sanitizer Changes — `InferenceService.swift`

Remove the `<think>` pattern from `AssistantResponseSanitizer.clean()`:
```
"(?is)<think>[\\s\\S]*?</think>"   ← delete this line
```
Thinking content is now extracted live during streaming; `clean()` is called only on the answer portion.

---

## New Components — `MessageBubbleView.swift`

### `ThinkingDisclosureRow`
- `@Binding var isExpanded: Bool`
- Input: `message.thinkingContent`, `message.thinkingDurationSeconds`
- Purple accent (`#a855f7` / `AppTheme` equivalent)
- Header row: icon + "Thinking… [dots]" or "Thought for Xs" + chevron
- Expanded body: left-bordered block, italic text, `thinkingContent` rendered as plain text with blinking cursor while `thinkingDurationSeconds == nil`

### `SearchDisclosureRow`
- `@Binding var isExpanded: Bool`
- Input: `message.citations: [SearchCitation]`
- Teal accent
- Header row: icon + "Web Search" + "N sources" pill + chevron
- Expanded body: list of sources — title + snippet; each wrapped in `Link(destination: citation.url)`

### `MessageBubbleView` layout (assistant bubble VStack, top to bottom):
1. `SearchDisclosureRow` (if `!citations.isEmpty`) — at **top**, before answer text
2. `ThinkingDisclosureRow` (if `thinkingContent != nil`) — below search, above answer
3. Answer text (`MarkdownTextView`)
4. Citation pills (existing, unchanged)

---

## What Is Not Changed

- `AppStateStore` — same `messages[lastIdx]` mutation pattern
- `MLXInferenceService` / `LocalLlamaInferenceService` — stream unchanged
- `MarkdownTextView` — unchanged
- Citation pills at bubble bottom — unchanged
- `ChatMessage.Role.search` enum case — left in place (backwards compat for persisted sessions) but no new `.search` messages are created
