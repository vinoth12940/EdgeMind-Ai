# TODOS

## Post-V1 (after App Store submission)

### Flash Attention Per-Model Benchmark
**What:** Benchmark Qwen/Gemma specifically with flash attention on vs. off. Confirm 20-30% speedup claim and verify no output quality regression.
**Why:** Flash attention performance varies by model architecture. The claim is from LLaMA-family benchmarks. Our catalog uses different architectures.
**Where to start:** The 0.3.0 OSLog instrumentation is already in place — `LocalLlamaContext.generateStream` logs a `perf model=gguf tokens=N elapsed=X tok/s=Y` line at the end of every generation. Compare before/after on each catalog model on a physical device using Console.app or `log stream` (no debugger needed). Tune `DeviceCapabilityService.supportsFlashAttention()` gating if warranted.

