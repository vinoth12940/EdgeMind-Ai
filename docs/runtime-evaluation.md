# Runtime Evaluation & Architecture — Edge Mind Ai

## Status: Validated & In Production (v0.3.0)

Four on-device inference runtimes have been evaluated, integrated, and verified on Apple Silicon hardware:

### 1. llama.cpp (`.gguf`)
- **Runtime Backend**: `LocalLlamaInferenceService` via vendored `llama.xcframework` (build b8354).
- **Strengths**: Broad quantized model ecosystem (`Q4_K_M`), predictable RAM footprint, runs on both iOS Simulator and physical hardware.
- **Hardware Integration**: Metal flash-attention enabled on A15+, disabled on A10–A14 to prevent Metal shader issues.

### 2. Apple MLX (`.mlx`)
- **Runtime Backend**: `MLXInferenceService` via `mlx-swift-lm` (MLXLLM, MLXVLM).
- **Strengths**: Maximum throughput on Apple Silicon Neural Engine & GPU; supports multimodal VLMs (SigLIP vision tower).
- **Constraints**: Requires physical device with Apple Silicon (compiled out of simulator); vision prefill constrained to 192px / 4-bit KV cache on memory-constrained devices.

### 3. LiteRT-LM (`.litertlm`)
- **Runtime Backend**: `LiteRTInferenceService` via local package `Vendor/LiteRT-LM`.
- **Strengths**: Optimized Google Gemma 4 E2B/E4B task bundles; supports vision on E2B.
- **Constraints**: Clamped to 2,048 safe context tokens.

### 4. Apple Foundation Models (`.foundationModels`)
- **Runtime Backend**: `AppleFoundationModelService`.
- **Strengths**: Zero weight download, system-level efficiency, instant cold start.
- **Constraints**: Available only on compatible Apple Intelligence devices running supported OS versions.

### Cross-Runtime Memory Coordination
- `RuntimeMemoryCoordinator` enforces mutual exclusion across all four runtimes to prevent concurrent memory pressure.
- `AvailableMemoryGuard` verifies `os_proc_available_memory()` headroom before prefill/inference.
- Background eviction frees idle weights when `scenePhase == .background`.

