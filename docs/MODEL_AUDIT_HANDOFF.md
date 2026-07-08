# Model Audit Handoff — finishing the on-device verdicts

This documents the "make every catalog model work as intended" work done in the
current session and gives step-by-step instructions to finish the remaining
on-device audits. Written so Codex (or a human) can pick it up directly.

Repo: `/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai`
Device used: iPhone 17 Pro (`428A7E6B-8497-56D4-B7A2-02ABAD4FC996`), bundle `com.vinothrajalingam.EdgeMindAi`.

---

## 1. What was already fixed (code — all landed, 265 sim tests green)

| Area | File(s) | What changed |
|------|---------|--------------|
| **Root cause: audit refusal checker** | `EdgeMindAi/Services/Inference/ResponsibleAIGuard.swift` | `isSafeRefusal` rewritten. The old fixed-phrase list scored real refusals ("I can't provide instructions on how to…") as `rai-refusal-missing`, which cascaded good models to a **false `red`** verdict. Now a leading-window refusal-verb + assistance-verb matcher. Gotcha: `normalize` turns `can't`→`can t` (apostrophe→space). Tests in `EdgeMindAiTests/ResponsibleAIGuardTests.swift`. |
| Gemma 4 native tool calls | `StreamProcessor.swift` (`GemmaToolCallPayload`) | Gemma 4 emits `<|tool_call>call:NAME{key:<|"|>val<|"|>}<tool_call|>` (typed args, not JSON). Now parsed to `(name, argsJSON)`. Tests: `EdgeMindAiTests/GemmaToolCallPayloadTests.swift`. |
| Qwen 3.5 VL 4B image OOM | `MLXInferenceService.swift` (`isConstrainedVisionModel`, `isQwen35VL4B`) | The old vision-memory check matched `qwen3-vl-4b` but the real repo is `mlx-community/Qwen3.5-4B-4bit`, so it never matched → ran unbounded 384px path → OOM. Now 192px + `kvBits:4` + `prefillStepSize:16` + wired-memory ticket. |
| LFM2.5 context data | `MockCatalogData.swift` | 350M and 1.2B-Thinking were "128K"; per LiquidAI cards all LFM2.5-1.2B/350M are **32K**. Fixed. |
| Catalog vs profile vision mismatch | `ModelRuntimeResolver.swift` | Mismatch now compares app-level `supportsVision` (not upstream `sourceSupportsVision`), so deliberately text-only VLMs aren't flagged. |
| Guardrail tests | `EdgeMindAiTests/CatalogConsistencyTests.swift` | Unique IDs, runtime load-path, vision↔inputModes, red≠recommended, cross-runtime context agreement. |
| Secrets → Keychain | `KeychainSecretStore.swift`, `AppSettings.swift`, `AppStateStore.swift` | API key + HF token no longer persisted as plaintext in UserDefaults. |

## 2. Verified on device this session

- **Llama 3.2 1B (MLX): `red:raiSafety` → `green`.** All 9 audit cases passed after the checker fix. Already written back to catalog + `RuntimeProfiles.json` (green, testedDeviceTier pro, auditedAt 2026-07-05).
- **Ministral 3 3B Instruct (MLX): pending yellow → `green`.** All audit cases passed on iPhone 17 Pro on 2026-07-05. Written back to catalog + `RuntimeProfiles.json` (green, testedDeviceTier pro, auditedAt 2026-07-05).

## 3. Confirmed real (keep honest yellow — NOT a checker bug)

- **Phi 3.5 Mini (3.8B MLX)** — jetsam-killed mid-`longNarrative` generation, reproducibly. Real memory limit. Leave yellow (or, if desired, change the note to a memory-crash note).
- **SmolLM3 3B (MLX)** — completed on-device audit and failed `longNarrative` with `empty-output`, final verdict `red:longNarrative`. Removed from the shipped catalog and `RuntimeProfiles.json`; the shipped catalog policy/tests do not allow red or unsupported entries.

---

## 4. What remains — audit these one at a time

The first pass hung because heavy/reasoning models and HF downloads stall the
`devicectl --console` launch (DeepSeek stalled at download 0%), and macOS has no
GNU `timeout`. Run each model **individually** and watch for a 0% download stall.

Remaining pending-yellow MLX models (currently
`yellow("built-in-provider-model-pending-full-device-audit")` — the exact case
the checker fix unblocks):

| Model | catalogID | mlxModelID |
|-------|-----------|------------|
| DeepSeek R1 Distill Qwen 1.5B (MLX) | `FE1AA06F-5D48-594D-AFFA-FB360D0DE1FF` | `mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit` |

Different-reason yellows (audit separately, may legitimately stay yellow):

| Model | catalogID | Current yellow note |
|-------|-----------|---------------------|
| Gemma 3 1B Instruct (MLX) | `2D1A8162-56B2-530A-AC76-ACBDF74B61AB` | `audited-noisy-output-fabricated-sources` (quality, not safety) |
| Phi 3.5 Mini Instruct (MLX) | `788BFE23-3736-5360-8FAA-B86717BC310C` | crashes on generation (see §3) |
| Qwen 3.5 VL 4B (MLX) | `D9FB3D90-8705-5FED-9978-FFBCE6121CED` | `image-prefill-memory-killed…`; re-audit VISION after the Phase-2 fix |

Download-stalled attempts from the 2026-07-05 continuation:

| Model | Last observed state |
|-------|---------------------|
| DeepSeek R1 Distill Qwen 1.5B (MLX) | Stuck at `DOWNLOADING ... progress=0%`; stopped and app reinstalled. |
| Gemma 3 1B Instruct (MLX) | Stuck at `DOWNLOADING ... progress=0%`; stopped. Existing yellow quality note left unchanged. |
| Qwen 3.5 VL 4B (MLX) vision probe | Stuck at `DOWNLOADING ... progress=0%`; stopped and app reinstalled. Existing memory warning left unchanged. |
| Gemma 4 E2B Instruct (LiteRT-LM) | Download progressed to 22%, then stalled; stopped. No parser/runtime verdict from this run. |

## 5. How to run one audit

Prereqs (once): clear any stuck launchers, confirm the device, build+install the
current binary.

```bash
cd "/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai"
pkill -9 -f devicectl 2>/dev/null; sleep 2
xcrun devicectl list devices | grep -i connected            # confirm iPhone

# Build + install the current (fixed) binary:
xcodegen generate
xattr -cr .                                                 # avoid CodeSign "detritus" failures
xcodebuild build -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -destination 'id=428A7E6B-8497-56D4-B7A2-02ABAD4FC996' \
  -allowProvisioningUpdates -derivedDataPath build/device-audit
APP=$(find build/device-audit/Build/Products -name EdgeMindAi.app -maxdepth 3 | head -1)
xcrun devicectl device install app --device 428A7E6B-8497-56D4-B7A2-02ABAD4FC996 "$APP"
```

If the device build reaches the final app signing step and fails with
`resource fork, Finder information, or similar detritus not allowed`, the app
bundle may still be usable after clearing the generated product and re-signing:

```bash
APP="build/device-audit/Build/Products/Debug-iphoneos/EdgeMindAi.app"
ENT="build/device-audit/Build/Intermediates.noindex/EdgeMindAi.build/Debug-iphoneos/EdgeMindAi.build/EdgeMindAi.app.xcent"
xattr -cr "$APP"
codesign --force --sign 03C305285466DD536346CC62BC21D9659FA408B1 \
  --entitlements "$ENT" --timestamp=none --generate-entitlement-der "$APP"
xcrun devicectl device install app --device 428A7E6B-8497-56D4-B7A2-02ABAD4FC996 "$APP"
```

Run ONE model (keep the phone unlocked). `--localai-audit-case-timeout-sec`
bounds each case so a slow reasoning trace can't hang the run:

```bash
xcrun devicectl device process launch --console --terminate-existing \
  --device 428A7E6B-8497-56D4-B7A2-02ABAD4FC996 com.vinothrajalingam.EdgeMindAi \
  --localai-run-model-audit \
  --localai-audit-model "SmolLM3 3B (MLX)" \
  --localai-audit-case-timeout-sec 90 \
  --localai-audit-uninstall-after
```

Vision re-audit (Qwen 3.5 VL 4B, after the Phase-2 memory fix):

```bash
xcrun devicectl device process launch --console --terminate-existing \
  --device 428A7E6B-8497-56D4-B7A2-02ABAD4FC996 com.vinothrajalingam.EdgeMindAi \
  --localai-run-model-audit \
  --localai-audit-model "Qwen 3.5 VL 4B (MLX)" \
  --localai-audit-vision-only --localai-audit-source-vision \
  --localai-audit-case-timeout-sec 120 --localai-audit-uninstall-after
```

Gemma 4 E2B tool-call re-audit (exercises the new native-tool-call parser):

```bash
xcrun devicectl device process launch --console --terminate-existing \
  --device 428A7E6B-8497-56D4-B7A2-02ABAD4FC996 com.vinothrajalingam.EdgeMindAi \
  --localai-run-model-audit \
  --localai-audit-model "Gemma 4 E2B Instruct (LiteRT-LM)" \
  --localai-audit-case-timeout-sec 120
```

Launcher flags live in `EdgeMindAi/Services/Inference/HeadlessModelAuditLauncher.swift`.
Convenience scripts: `scratch/run-device-audit.sh`, `scratch/run-device-audit-remaining.sh`
(edit the model list; the `timeout` line was removed — macOS has no GNU `timeout`).

### Reading the result
Watch the console for:
```
[MODEL_AUDIT] CASE_RESULT model="…" case="…" pass=true/false note="…"
[MODEL_AUDIT] MODEL_DONE   model="…" verdict="green" | "yellow:reason" | "red:reason"
```
A per-run JSON report is also written on-device to
`Documents/audits/<runID>/<catalogID>.json` (and a `RuntimeProfiles.override.json`
override in Documents — this is device-only, DEBUG-only, and does NOT change the
shipped app).

### If a download stalls at 0%
It's usually a corrupt partial in the HF cache from an interrupted run. Delete the
app (removes its HF cache), reinstall, retry that one model. Or skip it and move on.

## 6. Writing verdicts back into the repo (the permanent change)

For each model that comes back **green**, edit BOTH files (mirror the Llama 3.2 1B
diff already in the tree):

1. `EdgeMindAi/State/MockCatalogData.swift` — for that model:
   - `runtimeStatus: .worksWithWarnings` → `.recommended`
   - `auditVerdict: .yellow("…")` → `.green`
   - add `testedDeviceTier: .pro` if missing
2. `EdgeMindAi/Resources/RuntimeProfiles.json` — find the block with the matching
   `catalogID` (table in §4) and set:
   - `"auditVerdict": { "kind": "green" }`
   - `"auditedAt": "<today ISO8601>"`, `"lastAuditedDeviceTier": "pro"`

If a model comes back **yellow for a real reason** (Phi 3.5 memory, Gemma 3 1B
noisy output), keep it yellow but update the note to reflect the real cause. If
a shipped catalog model comes back **red/unsupported**, remove it from
`MockCatalogData.swift` and remove the matching `RuntimeProfiles.json` block;
`ModelCatalogItemTests.test_shippedCatalogExcludesUnsupportedOrRedModels`
enforces this.

Then verify:
```bash
xcodegen generate
xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -destination 'platform=iOS Simulator,name=LocalAI iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```
`CatalogConsistencyTests` enforces that red models are never `.recommended`, so
green/yellow edits must stay self-consistent.

## 7. Not for git

`build/`, `scratch/*.log`, and on-device `Documents/audits/*` are throwaway. The
`scratch/run-device-audit*.sh` scripts are handy but optional to commit.
