# Runtime Evaluation

## Goal
Choose an iPhone-deployable local inference runtime before claiming broad model compatibility.

## Candidate Tracks
1. GGUF-compatible runtime
   - Good fit for curated downloadable models
   - Broad ecosystem support
   - Practical for small-model catalog workflows
2. MLX-backed runtime
   - Strong Apple-silicon story
   - Good alignment with the reference product positioning
   - Must be validated specifically for iPhone deployment constraints and packaging

## Recommendation
Run a short technical spike before deepening runtime integration:
- Load one small chat model on target device
- Measure cold start and first token latency
- Measure memory pressure and thermal behavior
- Confirm packaging/distribution strategy for downloadable models

## Exit Criteria
- One supported runtime can load at least one curated model on iPhone
- Generation latency is acceptable for chat
- Model install flow is feasible within app storage constraints
- No hidden dependency forces a cloud fallback
