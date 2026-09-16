---
name: app-store-release
description: Use when shipping Edge Mind Ai to TestFlight or the App Store — bumping the version/build, archiving, uploading, submitting for review, or checking review status. Also use when an upload or export fails with "Failed to Use Accounts", "No signing certificate iOS Distribution found", "Cloud signing permission error", "Invalid Pre-Release Train", "train version is closed", "CFBundleShortVersionString must contain a higher version", or codesign "resource fork, Finder information, or similar detritus not allowed".
---

# App Store Release (Edge Mind Ai)

Ship only a build verified on a physical device. Simulator runs and unit tests have
missed launch-blocking bugs before.

Uploading and submitting are outward-facing: confirm with the user before steps 6
and 8 unless they already said to ship.

## Reference facts

| Thing | Value |
|---|---|
| Bundle IDs | `com.vinothrajalingam.EdgeMindAi`, `.Share`, `.Widget` |
| Team ID | `43NV5DTHKG` |
| iPhone UDID | `00008150-00056CA11A6A401C` (iPhone 17 Pro, iOS 27.0) |
| Simulator UDID | `321D26B6-AE9B-40CF-87AE-0278B9240741` |
| Credentials | `~/private_keys/asc.env` (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`) |
| Python for ASC scripts | `$TMPDIR/asc3/bin/python` (3.12 + pyjwt/requests/cryptography — the system 3.9 cannot parse them) |

`devicectl` **intercepts dash-prefixed app arguments**, so trigger in-app probes with
environment variables instead: `DEVICECTL_CHILD_<NAME>=1 xcrun devicectl ...`.

## Steps

1. **Preflight.** Clean `git status`. Run the full test suite and
   `python3 scripts/verify_docs_freshness.py`. Both gates must be green — note the
   script and `DocumentationFreshnessTests` count test methods independently, so
   satisfy **both** when you change tests.

2. **Check live state first:** `set -a; source ~/private_keys/asc.env; set +a;
   $TMPDIR/asc3/bin/python scripts/asc_submit.py --check`. The status recorded in
   `AGENTS.md` may be stale.

3. **Pick numbers** in `project.yml`, then `xcodegen generate`, then **commit the
   regenerated `EdgeMindAi.xcodeproj/project.pbxproj`** (it is tracked, and the
   build number only reaches the build through regeneration):
   - Always increment `CURRENT_PROJECT_VERSION`.
   - If the current `MARKETING_VERSION` is approved (`READY_FOR_SALE` /
     `PENDING_DEVELOPER_RELEASE`), increment it too. Its train is closed.

4. **Update docs to match:** the `AGENTS.md` release-state bullet,
   `APP_STORE_LISTING.md` (header version, §5 "What's New", checklist build line),
   and `docs/runtime-evaluation.md`. Re-run the freshness script until 0 errors.
   §5 is the exact text the submit script sends to Apple.

5. **Device gate** on the unlocked iPhone — `xcrun devicectl list devices` must show
   `connected`/`available`, not `unavailable`. A locked phone refuses to launch
   (`BSErrorCodeDescription = Locked`), which looks like a build failure but isn't.
   ```bash
   xattr -cr EdgeMindAi Vendor EdgeMindShare EdgeMindWidget
   xcodebuild -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -configuration Release \
     -destination 'id=00008150-00056CA11A6A401C' -derivedDataPath /tmp/gate -allowProvisioningUpdates build
   xcrun devicectl device install app --device <udid> /tmp/gate/Build/Products/Release-iphoneos/EdgeMindAi.app
   xcrun devicectl device process launch --terminate-existing --device <udid> com.vinothrajalingam.EdgeMindAi
   sleep 30 && xcrun devicectl device info processes --device <udid> | grep -c "EdgeMindAi.app/EdgeMindAi"  # expect 1
   ```
   Then run the DEBUG probes against the Debug build (`AppleFoundationVisionProbe`):
   ```bash
   DEVICECTL_CHILD_FM_VISION_PROBE=1 xcrun devicectl device process launch --console --terminate-existing --device <udid> com.vinothrajalingam.EdgeMindAi
   DEVICECTL_CHILD_FM_TOOL_PROBE=1   ... # tool calling
   DEVICECTL_CHILD_DOC_PROBE=1       ... # document library + tool gates, end to end
   ```
   The console launch blocks, so background it and `sleep 70` before grepping for
   `FMPROBE`/`DOCPROBE`.

6. **Archive** (keep archives out of `~/Desktop`, which adds xattrs that break codesign):
   ```bash
   A=$TMPDIR/EdgeMindAi-$VER-$BUILD.xcarchive
   xattr -cr EdgeMindAi Vendor
   xcodebuild archive -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -configuration Release \
     -destination 'generic/platform=iOS' -archivePath "$A" -allowProvisioningUpdates
   ls "$A/dSYMs"   # must include CLiteRTLM.framework.dSYM
   ```

7. **Upload.** Try the normal path first, and if it fails see "Signing" below:
   ```bash
   xcodebuild -exportArchive -archivePath "$A" -exportOptionsPlist scripts/ExportOptions.plist \
     -exportPath $TMPDIR/export -allowProvisioningUpdates    # expect "UPLOAD SUCCEEDED"
   ```

8. **Wait for processing.** Repeat `--check` until `build=VALID`, usually 5–30 min.
   `asc_submit.py` exits 2 while the build is still processing.

9. **Submit:** `$TMPDIR/asc3/bin/python scripts/asc_submit.py`. It creates or reuses
   the version, attaches the build, sets What's New, and submits. Expect
   `state=WAITING_FOR_REVIEW`. To replace a build already in review, cancel the
   submission first (see below), then rerun this step.

10. **Record** the submission ID, version ID and state in the `AGENTS.md` release
    bullet, then commit and push.

## Signing: when the Xcode account is missing and there is no distribution cert

`xcodebuild -exportArchive` with `destination: upload` needs an authenticated **Xcode**
Apple Account, and it can only cloud-sign when that account already has a distribution
certificate. Being signed into System Settings → Apple Account (iCloud) does **not**
count — check the one the CLI reads:

```bash
defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists   # empty () == no Xcode account
security find-identity -v -p codesigning                                  # need "Apple Distribution"
```

If either is missing you get `Failed to Use Accounts`, `No signing certificate
"iOS Distribution" found`, or `Cloud signing permission error`. **You do not need the
user to sign in** — do it all with the App Store Connect API key, which already has
access (verify with `GET /v1/certificates`; a 200 means it can be used):

```bash
# 1. Create the distribution cert + IOS_APP_STORE profiles, install them,
#    and write a manual-signing ExportOptions plist. Safe to re-run.
scripts/asc_signing.sh bootstrap

# 2. Export locally. destination MUST be `export`, not `upload`.
scripts/asc_signing.sh export "$A"

# 3. Upload with the API key — no Xcode account involved.
scripts/asc_signing.sh upload "$A"-sibling/edgemind-ipa/EdgeMindAi.ipa
```

Mechanics worth knowing if you have to do it by hand:

- Create the cert with `POST /v1/certificates` (`certificateType: DISTRIBUTION`) and a
  locally generated CSR, then import key+cert into the login keychain.
- **OpenSSL 3's default PKCS#12 is unreadable by macOS `security`** — export with
  `openssl pkcs12 -export -legacy ...` or the import dies with
  `MAC verification failed (wrong password?)`.
- `profileContent` from the API is **base64**; decode it before `security cms -D`,
  otherwise profile parsing fails with `Error Reading File`.
- Profiles are matched by UUID under
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<uuid>.mobileprovision`.
- `altool` finds the key at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`;
  it prints `UPLOAD SUCCEEDED` plus a Delivery UUID.

## Replacing a build that is already in review

A version in `WAITING_FOR_REVIEW` / `IN_REVIEW` cannot have its build swapped. Cancel
the submission, attach the new build, and resubmit:

```python
requests.patch(f"{BASE}/reviewSubmissions/{id}", headers=H,
               json={"data": {"type": "reviewSubmissions", "id": id,
                              "attributes": {"canceled": True}}})
```

The version then reads `DEVELOPER_REJECTED`, and the next `asc_submit.py` run attaches
the new build and submits normally. Do this rather than shipping a known-bad build.

## Failures

| Symptom | Fix |
|---|---|
| `Failed to Use Accounts` / `No signing certificate "iOS Distribution" found` / `Cloud signing permission error` | No usable Xcode account and/or no distribution cert. Run `scripts/asc_signing.sh bootstrap`, export with `destination: export`, and upload with `asc_signing.sh upload`. |
| `security import ... MAC verification failed` | PKCS#12 made by OpenSSL 3. Re-export with `-legacy`. |
| `security cms -D` → `Error Reading File` | The file is base64 (`profileContent`). `base64 -D` it first. |
| `Invalid Pre-Release Train` / `train version '<v>' is closed` / `must contain a higher version` | That version is approved. Bump `MARKETING_VERSION`, keep the build number, redo steps 3, 4 and 6. |
| codesign `detritus not allowed` | `xattr -cr EdgeMindAi Vendor`; build to default DerivedData or `$TMPDIR`, never under `~/Desktop`. |
| Device launch fails with `Locked` / `not unlocked` | The phone is asleep or locked. `BSErrorCodeDescription = Locked`. Unlock it and leave the screen on; retry. |
| Device build fails with `cannot find '<x>' in scope` in MLX/LiteRT code | The simulator compiles the `#else` branch of `#if canImport(...) && !targetEnvironment(simulator)`, so a green simulator build never type-checks those files. Always device-build after touching them. |
| `xcodegen generate` fails with duplicate declarations | Finder duplicates (`Foo 2.swift`) are on disk. XcodeGen globs the source tree and pulls them in. Delete every `* 2.*` file and any stray `EdgeMindAi N.xcodeproj`. |
| `Missing env vars` | `~/private_keys/asc.env` needs `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`. Never commit these values. |
| `Could not create review submission` | A draft submission already exists. Finish or cancel it, then rerun. |
| Tests fail after device debugging | Device prefs leak into the simulator's UserDefaults. `xcrun simctl spawn <sim> defaults delete com.vinothrajalingam.EdgeMindAi`. |
| `README.md unit test count mismatch` | Update the `\| Unit tests \|` row to the number the failing gate reports, then re-run **both** gates. |
