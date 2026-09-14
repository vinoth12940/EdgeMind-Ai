#!/usr/bin/env python3
"""App Store Connect submission for Edge Mind Ai.

Reads MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml and the
"What's New" block from APP_STORE_LISTING.md §5, then (default mode) creates or
reuses the App Store version, attaches the build, sets What's New, and submits
for review.

Credentials come from the environment (never commit them):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH
Load them with:  set -a; source ~/private_keys/asc.env; set +a

Usage:
  python3 scripts/asc_submit.py --check    # read-only: build + version state
  python3 scripts/asc_submit.py            # attach + submit for review

Exit codes: 0 ok, 1 error, 2 build still processing (retry later).
"""

import argparse
import os
import re
import sys
import time
from pathlib import Path

import jwt
import requests

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "com.vinothrajalingam.EdgeMindAi"
BASE_URL = "https://api.appstoreconnect.apple.com/v1"
SUBMITTED_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "READY_FOR_SALE"}


def fail(message: str, code: int = 1) -> None:
    print(f"❌ {message}")
    sys.exit(code)


def read_project_versions() -> tuple[str, str]:
    text = (ROOT / "project.yml").read_text()
    marketing = re.search(r"^\s*MARKETING_VERSION:\s*([0-9.]+)\s*$", text, re.M)
    build = re.search(r"^\s*CURRENT_PROJECT_VERSION:\s*([0-9]+)\s*$", text, re.M)
    if not marketing or not build:
        fail("Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml")
    return marketing.group(1), build.group(1)


def read_whats_new() -> str:
    text = (ROOT / "APP_STORE_LISTING.md").read_text()
    match = re.search(r"## 5\. What's New in This Version\s*```\s*\n(.*?)\n```", text, re.S)
    if not match or not match.group(1).strip():
        fail("Could not read the What's New code block from APP_STORE_LISTING.md §5")
    return match.group(1).strip()


class ASC:
    def __init__(self) -> None:
        missing = [name for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH") if not os.environ.get(name)]
        if missing:
            fail(f"Missing env vars: {', '.join(missing)} (source ~/private_keys/asc.env)")
        key = Path(os.environ["ASC_KEY_PATH"]).expanduser().read_text()
        token = jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
            key,
            algorithm="ES256",
            headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
        )
        self.headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    def request(self, method: str, path: str, ok: tuple[int, ...] = (200, 201, 204), **kwargs):
        response = requests.request(method, f"{BASE_URL}{path}", headers=self.headers, timeout=60, **kwargs)
        if response.status_code not in ok:
            print(f"{method} {path} → {response.status_code}\n{response.text[:1500]}")
            return None
        return response.json() if response.content else {}


def find_app(asc: ASC) -> str:
    data = asc.request("GET", "/apps", params={"filter[bundleId]": BUNDLE_ID})
    if not data or not data.get("data"):
        fail("App not found")
    return data["data"][0]["id"]


def find_build(asc: ASC, app_id: str, version: str, build: str) -> tuple[str | None, str]:
    data = asc.request(
        "GET",
        "/builds",
        params={
            "filter[app]": app_id,
            "filter[version]": build,
            "filter[preReleaseVersion.version]": version,
            "sort": "-uploadedDate",
            "limit": 5,
        },
    )
    if not data or not data.get("data"):
        return None, "NOT_FOUND"
    for item in data["data"]:
        if item["attributes"].get("processingState") == "VALID":
            return item["id"], "VALID"
    return None, data["data"][0]["attributes"].get("processingState", "UNKNOWN")


def find_version(asc: ASC, app_id: str, version: str) -> tuple[str | None, str]:
    # GET /appStoreVersions (collection) returns 403; use the per-app relationship.
    data = asc.request(
        "GET",
        f"/apps/{app_id}/appStoreVersions",
        params={"filter[platform]": "IOS", "filter[versionString]": version},
    )
    if data and data.get("data"):
        item = data["data"][0]
        return item["id"], item["attributes"].get("appStoreState", "")
    return None, "NOT_CREATED"


def create_version(asc: ASC, app_id: str, version: str) -> str:
    payload = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {"versionString": version, "platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    result = asc.request("POST", "/appStoreVersions", json=payload)
    if not result:
        fail(f"Could not create version {version} (is a newer version already open or approved?)")
    return result["data"]["id"]


def set_whats_new(asc: ASC, version_id: str, whats_new: str) -> None:
    data = asc.request("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    for loc in (data or {}).get("data", []):
        if loc["attributes"].get("locale", "").startswith("en"):
            payload = {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": whats_new}}}
            if not asc.request("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", json=payload):
                fail("Could not update What's New")
            return
    payload = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": "en-US", "whatsNew": whats_new},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
        }
    }
    if not asc.request("POST", "/appStoreVersionLocalizations", json=payload):
        fail("Could not create en-US localization")


def submit(asc: ASC, app_id: str, version_id: str) -> str:
    created = asc.request(
        "POST",
        "/reviewSubmissions",
        json={
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    if not created:
        fail("Could not create review submission (an open draft submission may already exist in App Store Connect)")
    submission_id = created["data"]["id"]
    item = asc.request(
        "POST",
        "/reviewSubmissionItems",
        json={
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }
        },
    )
    if not item:
        fail(f"Could not add version to review submission {submission_id}")
    result = asc.request(
        "PATCH",
        f"/reviewSubmissions/{submission_id}",
        json={"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}},
    )
    if not result:
        fail(f"Could not submit review submission {submission_id}")
    print(f"✅ Submitted: review submission {submission_id} state={result['data']['attributes'].get('state')}")
    return submission_id


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="read-only status check; changes nothing")
    args = parser.parse_args()

    version, build = read_project_versions()
    whats_new = read_whats_new()
    asc = ASC()
    app_id = find_app(asc)
    build_id, build_state = find_build(asc, app_id, version, build)
    version_id, version_state = find_version(asc, app_id, version)

    print(f"App {app_id} | {version} ({build}) | build={build_state} | version={version_state}")
    if args.check:
        return

    if not build_id:
        if build_state in ("PROCESSING", "NOT_FOUND"):
            fail(f"Build {version} ({build}) is {build_state}; retry in a few minutes", code=2)
        fail(f"Build {version} ({build}) is {build_state}")
    if version_state in SUBMITTED_STATES:
        print(f"Version {version} is already {version_state}; nothing to submit.")
        return

    if not version_id:
        version_id = create_version(asc, app_id, version)
        print(f"✅ Created version {version} ({version_id})")
    if asc.request("PATCH", f"/appStoreVersions/{version_id}/relationships/build",
                   json={"data": {"type": "builds", "id": build_id}}) is None:
        fail("Could not attach build")
    print(f"✅ Attached build {build} ({build_id})")
    set_whats_new(asc, version_id, whats_new)
    print("✅ What's New set from APP_STORE_LISTING.md")
    submit(asc, app_id, version_id)
    print(f"Version ID: {version_id}")


if __name__ == "__main__":
    main()
