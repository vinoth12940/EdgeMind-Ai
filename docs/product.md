# Product Scope — Edge Mind Ai

## Summary
Edge Mind Ai is an iPhone & iPad native SwiftUI app for private, on-device AI chat and multimodal inference. Users run curated open-source LLMs and VLMs locally across four runtimes (llama.cpp GGUF, Apple MLX, LiteRT-LM, and Apple Foundation Models). Live web search is optional and explicit per prompt.

## Screens
- **Chat**: Streaming token output, thinking lane, quick model switcher, image attachments, voice dictation/playback, and agentic tool loop.
- **Models**: Device-audited catalog with "Best for your iPhone" tier badges, "Vision & Camera Ready" shelf, and download management.
- **History**: Local session management with session search.
- **Settings**: Web search provider keys, Hugging Face tokens in Keychain, performance stats toggle, and appearance controls.

## Core Principles
- Local-first by default: 100% on-device inference without cloud dependencies.
- Web search only when explicitly enabled by the user with their own API keys.
- Curated, device-audited models over unchecked compatibility claims.
- Memory protection: Headroom pre-flight checks and background weight eviction to prevent Jetsam crashes.
- Accurate privacy disclosures: Zero telemetry, zero analytics, zero cloud sync.

