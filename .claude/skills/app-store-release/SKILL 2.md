---
name: app-store-release
description: Use when shipping Edge Mind Ai to TestFlight or the App Store — bumping the version/build, archiving, uploading, submitting for review, or checking review status. Also use when an upload fails with "Invalid Pre-Release Train", "train version is closed", "CFBundleShortVersionString must contain a higher version", or codesign "resource fork, Finder information, or similar detritus not allowed".
---

# App Store Release (Edge Mind Ai)

Ship only a build verified on a physical device. Unit tests and simulator runs have missed launch-blocking bugs (the iOS 26.6.1 `defaultScrollAnchor` watchdog hang never reproduced on the 26.5 simulator).

Uploading and submitting are outward-facing: confirm with the user before steps 6 and 8 unless they already said to ship.

## Steps

1. **Preflight.** Clean `git status`. Run the full test suite and `python3 scripts/verify_docs_freshness.py` (commands in `CLAUDE.md`).
2. **Check live state first:** `set -a; source ~/private_keys/asc.env; set +a; python3 scripts/asc_submit.py --check`. The status in `AGENTS.md` may be stale.
3. **Pick numbers** in `project.yml`, then `xcodegen generate`:
   - Always increment `CURRENT_PROJECT_VERSION`.
   - If the current `MARKETING_VERSION` is approved (`READY_FOR_SALE` / `PENDING_DEVELOPER_RELEASE`), increment it too. Its train is closed.
4. **Update docs to match:** the `AGENTS.md` release-state bullet, `APP_STORE_LISTING.md` (header version, §5 "What's New", checklist build line), and the `docs/runtime-evaluation.md` status line. Re-run the freshness script until it shows 0 errors. §5 is the text the submit script sends to Apple.
5. **Device gate** on the unlocked iPhone (UDID `428A7E6B-8497-56D4-B7A2-02ABAD4FC996`):
   - Build Release to default DerivedData, install, then launch with `devicectl ... process launch --console --terminate-existing`.
   - The app must stay alive for more than 30 seconds with no new `EdgeMindAi-*.ips` in `devicectl device info files --domain-type systemCrashLogs`.
   - Run the audit on installed models: `--localai-run-model-audit --localai-audit-require-installed --localai-audit-model "<name>" --localai-audit-case-timeout-sec 120`. Add `--localai-audit-all-runtimes` for GGUF.
6. **Archive + upload.** Keep archives out of `~/Desktop`, which adds xattrs that break codesign:
   ```bash
   A=$TMPDIR/EdgeMindAi-$VER-$BUILD.xcarchive
   xattr -cr EdgeMindAi Vendor
   xcodebuild archive -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -configuration Release \
     -destination 'generic/platform=iOS' -archivePath "$A" -allowProvisioningUpdates
   ls "$A/dSYMs"   # must include CLiteRTLM.framework.dSYM
   xcodebuild -exportArchive -archivePath "$A" -exportOptionsPlist scripts/ExportOptions.plist \
     -exportPath $TMPDIR/export -allowProvisioningUpdates   # expect "Upload succeeded"
   ```
7. **Wait for processing.** Repeat `--check` until `build=VALID`, usually 5–30 minutes. Submit exits with code 2 while the build is still processing.
8. **Submit:** `python3 scripts/asc_submit.py`. It creates or reuses the version, attaches the build, sets What's New, and submits. Expect `state=WAITING_FOR_REVIEW`.
9. **Record** the submission ID, version ID and state in the `AGENTS.md` release bullet, then commit.

## Failures

| Symptom | Fix |
|---|---|
| `Invalid Pre-Release Train` / `train version '<v>' is closed` / `must contain a higher version` | That version is approved. Bump `MARKETING_VERSION`, keep the build number, redo steps 3, 4 and 6. |
| codesign `detritus not allowed` | `xattr -cr EdgeMindAi Vendor`. Build to default DerivedData or `$TMPDIR`, never under `~/Desktop`. |
| Device launch dies at about 20 s, `0x8BADF00D scene-create watchdog` | Real hang, don't ship. Pull the `.ips` and use superpowers:systematic-debugging. First confirm the phone was unlocked (report says `ProcessVisibility: Foreground`). |
| Tests fail after device debugging | Device prefs imported into the simulator pollute UserDefaults. Run `xcrun simctl spawn <sim> defaults delete com.vinothrajalingam.EdgeMindAi`. |
| `Missing env vars` | `~/private_keys/asc.env` needs `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`. Never commit these values. |
| `Could not create review submission` | A draft submission already exists. Finish or remove it in App Store Connect, then rerun. |
| Credential reads denied in auto mode | The permission classifier blocks key access. Ask the user to switch modes (Shift+Tab) or add a `/permissions` rule. Don't route around it. |
