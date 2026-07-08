#!/bin/zsh
# Phase 4 on-device model audit — Edge Mind Ai
# Prereqs: iPhone "Vinoths" (428A7E6B-...) connected + unlocked, app already built
# to build/device-audit (done). Results stream as [MODEL_AUDIT] lines; verdicts
# appear as: MODEL_DONE model="..." verdict="green|yellow:reason|red:reason".
set -e
DEVICE="428A7E6B-8497-56D4-B7A2-02ABAD4FC996"
BUNDLE="com.vinothrajalingam.EdgeMindAi"
APP=$(find build/device-audit/Build/Products -name "EdgeMindAi.app" -maxdepth 3 | head -1)
LOG=scratch/device-audit-$(date +%Y%m%d-%H%M).log

echo "Installing $APP" | tee "$LOG"
xcrun devicectl device install app --device "$DEVICE" "$APP"

# The 7 pending-yellow MLX models (uninstall-after keeps device storage clean),
# then the two capability probes.
MODELS=(
  "Llama 3.2 1B Instruct (MLX)"
  "Phi 3.5 Mini Instruct (MLX)"
  "DeepSeek R1 Distill Qwen 1.5B (MLX)"
  "Ministral 3 3B Instruct (MLX)"
  "SmolLM3 3B (MLX)"
  "Gemma 3 1B Instruct (MLX)"
)
for MODEL in "${MODELS[@]}"; do
  echo "=== AUDIT: $MODEL ===" | tee -a "$LOG"
  xcrun devicectl device process launch --console --device "$DEVICE" "$BUNDLE" \
    --localai-run-model-audit \
    --localai-audit-model "$MODEL" \
    --localai-audit-uninstall-after 2>&1 | tee -a "$LOG" | grep "MODEL_AUDIT" || true
done

# Qwen 3.5 VL 4B: source-vision probe (verifies the new constrained-vision path).
echo "=== AUDIT: Qwen 3.5 VL 4B vision probe ===" | tee -a "$LOG"
xcrun devicectl device process launch --console --device "$DEVICE" "$BUNDLE" \
  --localai-run-model-audit \
  --localai-audit-model "Qwen 3.5 VL 4B (MLX)" \
  --localai-audit-vision-only \
  --localai-audit-source-vision \
  --localai-audit-uninstall-after 2>&1 | tee -a "$LOG" | grep "MODEL_AUDIT" || true

# Gemma 4 E2B (LiteRT): full re-audit — exercises the new native tool-call parser.
echo "=== AUDIT: Gemma 4 E2B (LiteRT) ===" | tee -a "$LOG"
xcrun devicectl device process launch --console --device "$DEVICE" "$BUNDLE" \
  --localai-run-model-audit \
  --localai-audit-model "Gemma 4 E2B Instruct (LiteRT-LM)" 2>&1 | tee -a "$LOG" | grep "MODEL_AUDIT" || true

echo "=== DONE — verdicts: ===" | tee -a "$LOG"
grep "MODEL_DONE" "$LOG" || echo "(none captured)"
