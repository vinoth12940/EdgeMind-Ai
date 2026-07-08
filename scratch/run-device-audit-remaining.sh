#!/bin/zsh
# Phase 4 continuation — bounded re-run of the remaining models.
# Per-case timeout (90s) so a slow/hanging model (e.g. reasoning traces) can't
# stall the whole run the way the first pass did. Phi 3.5 Mini is intentionally
# skipped: it reproducibly crashes on longNarrative (real memory limit → honest yellow).
set -e
DEVICE="428A7E6B-8497-56D4-B7A2-02ABAD4FC996"
BUNDLE="com.vinothrajalingam.EdgeMindAi"
LOG=scratch/device-audit-remaining-$(date +%Y%m%d-%H%M).log
: > "$LOG"

run_one() {
  local label="$1"; shift
  echo "=== AUDIT: $label ===" | tee -a "$LOG"
  # No GNU `timeout` on macOS; the app bounds each case via
  # --localai-audit-case-timeout-sec and _exit(0)s when the model finishes.
  xcrun devicectl device process launch --console --terminate-existing \
    --device "$DEVICE" "$BUNDLE" \
    --localai-run-model-audit \
    --localai-audit-case-timeout-sec 90 \
    "$@" 2>&1 | tee -a "$LOG" | grep -E "MODEL_AUDIT\]" || true
}

for MODEL in \
  "DeepSeek R1 Distill Qwen 1.5B (MLX)" \
  "SmolLM3 3B (MLX)" \
  "Gemma 3 1B Instruct (MLX)" \
  "Ministral 3 3B Instruct (MLX)"; do
  run_one "$MODEL" --localai-audit-model "$MODEL" --localai-audit-uninstall-after
done

# Qwen 3.5 VL 4B: source-vision probe — verifies the new constrained-vision path.
run_one "Qwen 3.5 VL 4B vision" \
  --localai-audit-model "Qwen 3.5 VL 4B (MLX)" \
  --localai-audit-vision-only --localai-audit-source-vision --localai-audit-uninstall-after

# Gemma 4 E2B (LiteRT): exercises the new native tool-call parser.
run_one "Gemma 4 E2B (LiteRT)" \
  --localai-audit-model "Gemma 4 E2B Instruct (LiteRT-LM)"

echo "=== VERDICTS ===" | tee -a "$LOG"
grep "MODEL_DONE" "$LOG" || echo "(none captured)"
