#!/usr/bin/env bash
#
# App Store signing + upload WITHOUT an Xcode Apple Account.
#
# WHY THIS EXISTS
# ---------------
# `xcodebuild -exportArchive` with `destination: upload` needs an authenticated
# Xcode Apple Account, and it can only cloud-sign when that account already has a
# distribution certificate. When Xcode has no developer account
# (`Xcode > Settings > Accounts` is empty — note this is SEPARATE from being
# signed into System Settings > Apple Account for iCloud) or the account has no
# distribution certificate, export dies with one of:
#
#     error: exportArchive Failed to Use Accounts
#     error: exportArchive No signing certificate "iOS Distribution" found
#     error: exportArchive Cloud signing permission error
#
# This script does the same job with only the App Store Connect API key, which
# `scripts/asc_submit.py` already uses. There is no need to sign Xcode in at all.
#
# USAGE
# -----
#   scripts/asc_signing.sh bootstrap            # create cert + App Store profiles (safe to re-run)
#   scripts/asc_signing.sh export  <archive>    # export a signed .ipa next to the archive
#   scripts/asc_signing.sh upload  <ipa>        # upload the .ipa with the API key
#   scripts/asc_signing.sh all     <archive>    # export + upload
#
# Requires `~/private_keys/asc.env` (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH) and
# the Python 3.12 venv used by asc_submit.py (override with ASC_PYTHON).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${ASC_SIGNING_DIR:-/tmp/edgemind-signing}"
ASC_PYTHON="${ASC_PYTHON:-$TMPDIR/asc3/bin/python}"
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

TEAM_ID="43NV5DTHKG"
BUNDLE_IDS=(
  "com.vinothrajalingam.EdgeMindAi"
  "com.vinothrajalingam.EdgeMindAi.Share"
  "com.vinothrajalingam.EdgeMindAi.Widget"
)

die() { echo "error: $*" >&2; exit 1; }

load_credentials() {
  # shellcheck disable=SC1090
  set -a; source "$HOME/private_keys/asc.env"; set +a
  [ -n "${ASC_KEY_ID:-}" ] || die "ASC_KEY_ID missing (source ~/private_keys/asc.env)"
  [ -n "${ASC_ISSUER_ID:-}" ] || die "ASC_ISSUER_ID missing"
  [ -f "${ASC_KEY_PATH:-}" ] || die "ASC_KEY_PATH does not point at a .p8 file"
  [ -x "$ASC_PYTHON" ] || die "python not found at $ASC_PYTHON (set ASC_PYTHON)"
}

# ---------------------------------------------------------------------------
# bootstrap: create an Apple Distribution certificate and IOS_APP_STORE profiles
# ---------------------------------------------------------------------------
bootstrap() {
  load_credentials
  mkdir -p "$WORK" "$PROFILE_DIR"
  cd "$WORK"

  if security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
    echo "==> distribution identity already in the keychain, skipping certificate creation"
  else
    echo "==> generating key + CSR and registering an Apple Distribution certificate"
    "$ASC_PYTHON" - <<'PY'
import os, time, jwt, requests, subprocess
BASE = "https://api.appstoreconnect.apple.com/v1"
key = open(os.environ["ASC_KEY_PATH"]).read()
tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "exp": int(time.time()) + 900,
                  "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                 headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
H = {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}

subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                "-keyout", "dist.key", "-out", "dist.csr",
                "-subj", "/CN=EdgeMind Distribution/O=Vinoth Rajalingam/C=US"],
               check=True, capture_output=True)

r = requests.post(f"{BASE}/certificates", headers=H, json={"data": {"type": "certificates",
    "attributes": {"certificateType": "DISTRIBUTION", "csrContent": open("dist.csr").read()}}})
if r.status_code >= 300:
    raise SystemExit(f"certificate create failed {r.status_code}: {r.text[:300]}")
d = r.json()["data"]
open("certid.txt", "w").write(d["id"])
open("dist.cer.b64", "w").write(d["attributes"]["certificateContent"])
print(f"    certificate {d['id']} expires {d['attributes'].get('expirationDate')}")
PY

    # OpenSSL 3 defaults to PKCS#12 encryption macOS `security` cannot verify;
    # `-legacy` is required or the import fails with "MAC verification failed".
    base64 -D -i dist.cer.b64 -o dist.cer
    openssl x509 -inform DER -in dist.cer -out dist.pem
    rm -f dist.p12
    openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12 \
      -passout pass:edgemind -name "Apple Distribution: Vinoth Rajalingam ($TEAM_ID)"
    security import dist.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P edgemind \
      -T /usr/bin/codesign -T /usr/bin/security
    echo "==> identity imported"
  fi

  echo "==> creating App Store provisioning profiles"
  "$ASC_PYTHON" - <<'PY'
import os, time, jwt, requests
BASE = "https://api.appstoreconnect.apple.com/v1"
key = open(os.environ["ASC_KEY_PATH"]).read()
tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "exp": int(time.time()) + 900,
                  "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                 headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
H = {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}
CERT = open("certid.txt").read().strip()
IDS = ["com.vinothrajalingam.EdgeMindAi",
       "com.vinothrajalingam.EdgeMindAi.Share",
       "com.vinothrajalingam.EdgeMindAi.Widget"]

# Existing profiles, keyed by name, so re-running does not create duplicates.
existing = {p["attributes"]["name"]: p for p in
            requests.get(f"{BASE}/profiles", headers=H, params={"limit": 200}).json().get("data", [])}

for ident in IDS:
    found = requests.get(f"{BASE}/bundleIds", headers=H, params={"filter[identifier]": ident}).json().get("data", [])
    if not found:
        raise SystemExit(f"{ident}: bundle id is not registered in the developer portal")
    name = f"EdgeMindAi AppStore {ident.split('.')[-1]}"

    if name in existing:
        a = existing[name]
        print(f"    {ident} -> reusing profile {a['id']} ({a['attributes'].get('profileState')})")
    else:
        p = requests.post(f"{BASE}/profiles", headers=H, json={"data": {"type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": found[0]["id"]}},
                              "certificates": {"data": [{"type": "certificates", "id": CERT}]}}}})
        if p.status_code >= 300:
            raise SystemExit(f"{ident}: profile create failed {p.status_code}: {p.text[:300]}")
        a = p.json()["data"]
        print(f"    {ident} -> created profile {a['id']} ({a['attributes'].get('profileState')})")

    # profileContent is BASE64 — decoding is mandatory, `security cms` cannot read it raw.
    open(f"{ident}.b64", "w").write(a["attributes"]["profileContent"])
PY

  for ident in "${BUNDLE_IDS[@]}"; do
    base64 -D -i "$WORK/$ident.b64" -o "$WORK/$ident.mobileprovision"
    security cms -D -i "$WORK/$ident.mobileprovision" > "$WORK/$ident.plist"
    uuid=$(/usr/libexec/PlistBuddy -c "Print :UUID" "$WORK/$ident.plist")
    cp "$WORK/$ident.mobileprovision" "$PROFILE_DIR/$uuid.mobileprovision"
    echo "    installed $ident ($uuid)"
  done

  write_export_options
  echo "==> done. Signing is bootstrapped; run 'asc_signing.sh upload <ipa>' after exporting."
}

write_export_options() {
  local plist="$WORK/ExportOptions-manual.plist"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    echo '  <key>method</key><string>app-store-connect</string>'
    # `export`, NOT `upload`: the upload destination is what demands an Xcode account.
    echo '  <key>destination</key><string>export</string>'
    echo "  <key>teamID</key><string>$TEAM_ID</string>"
    echo '  <key>signingStyle</key><string>manual</string>'
    echo '  <key>signingCertificate</key><string>Apple Distribution</string>'
    echo '  <key>provisioningProfiles</key><dict>'
    for ident in "${BUNDLE_IDS[@]}"; do
      local uuid
      uuid=$(/usr/libexec/PlistBuddy -c "Print :UUID" "$WORK/$ident.plist" 2>/dev/null || echo "")
      [ -n "$uuid" ] && echo "    <key>$ident</key><string>$uuid</string>"
    done
    echo '  </dict>'
    echo '  <key>uploadSymbols</key><true/>'
    echo '  <key>manageAppVersionAndBuildNumber</key><false/>'
    echo '</dict></plist>'
  } > "$plist"
  echo "==> wrote $plist"
}

# ---------------------------------------------------------------------------
# export: sign the archive into a locally exported .ipa
# ---------------------------------------------------------------------------
do_export() {
  local archive="${1:-}"
  [ -n "$archive" ] || die "usage: asc_signing.sh export <path.xcarchive>"
  [ -d "$archive" ] || die "archive not found: $archive"
  [ -f "$WORK/ExportOptions-manual.plist" ] || write_export_options

  local out; out="$(dirname "$archive")/edgemind-ipa"
  rm -rf "$out"
  xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$WORK/ExportOptions-manual.plist" -exportPath "$out"
  echo "==> ipa: $out/EdgeMindAi.ipa"
}

# ---------------------------------------------------------------------------
# upload: send the .ipa with the API key (no Xcode account involved)
# ---------------------------------------------------------------------------
do_upload() {
  local ipa="${1:-}"
  [ -n "$ipa" ] || die "usage: asc_signing.sh upload <path.ipa>"
  [ -f "$ipa" ] || die "ipa not found: $ipa"
  load_credentials

  mkdir -p "$HOME/.appstoreconnect/private_keys"
  cp "$ASC_KEY_PATH" "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

  xcrun altool --upload-app -f "$ipa" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
}

case "${1:-}" in
  bootstrap) bootstrap ;;
  export)    shift; do_export "${1:-}" ;;
  upload)    shift; do_upload "${1:-}" ;;
  all)       shift; do_export "${1:-}"; do_upload "$(dirname "${1:-}")/edgemind-ipa/EdgeMindAi.ipa" ;;
  *) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 1 ;;
esac
