# Product Scope

## Summary
Private Edge Chat is an iPhone-first SwiftUI app for private, on-device AI chat. Users install a curated set of small open-source models, choose the model they prefer, and chat in a dark native interface. Live web search is optional and explicit per prompt.

## V1 Screens
- Chat
- Models
- History
- Settings

## V1 Principles
- Local-first by default
- Web search only when explicitly enabled
- Curated model support over inflated compatibility claims
- Privacy messaging must be accurate
- Architecture should leave room for iPad, Mac, vision, and voice later

## Key UX Contract
- First run should feel simple: choose model, chat immediately.
- Users should always know whether a response came from local-only context or included live web context.
- Default model choice should be persistent and easy to change.
