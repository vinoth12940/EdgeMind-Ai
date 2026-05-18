# TODOS

## Post-V1 (after App Store submission)

### OOM Mid-Inference Handler
**What:** Register for `UIApplication.didReceiveMemoryWarningNotification`. On warning, cancel active inference task, set `activeContext = nil`, show user: "Your device needed memory — response was interrupted."
**Why:** Without this, iOS terminates the process silently (jetsam) during long inference on 4GB devices. Users see a crash, not an error.
**Where to start:** `LocalLlamaRuntime` actor + `ChatView.swift` (handle generation cancellation gracefully)

### Flash Attention Per-Model Benchmark
**What:** After enabling flash attention on A15+ (already in V1 scope), benchmark Qwen/Gemma specifically. Confirm 20-30% speedup claim and verify no output quality regression.
**Why:** Flash attention performance varies by model architecture. The claim is from LLaMA-family benchmarks. Our catalog uses different architectures.
**Where to start:** Add token/sec measurement to the OSLog output in `LocalLlamaContext`, compare before/after on each catalog model.

### Citation Data Model Refactor
**What:** Remove the `.search` message type from `ChatMessage.Role`. Citations are already attached to `ChatMessage.citations: [SearchCitation]`. Instead of prepending a sibling `.search` message in `ChatView.sendMessage()`, show a "Sources" footer in the assistant bubble only.
**Why:** The current model creates an orphaned `.search` message if inference fails or is cancelled. The assistant message already holds citations — just render them there.
**Where to start:** `ChatMessage.Role` enum, message rendering in `MessageBubbleView`. The citation ordering fix (no longer prepending `.search` before the assistant placeholder) has already shipped.
