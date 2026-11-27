"""Turns on the iCloud capability (key-value storage only, no CloudKit) for the app's
App ID through the App Store Connect API. Safe to run twice: it does nothing if iCloud
is already on. Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH from the environment and
never prints the key."""
import json
import os
import sys
import time

import jwt
import requests

BUNDLE_ID = "app.fiveskies.ios"
API = "https://api.appstoreconnect.apple.com/v1"


def token():
    with open(os.environ["ASC_KEY_PATH"]) as handle:
        key = handle.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, **kwargs):
    response = requests.request(
        method, API + path, headers={"Authorization": "Bearer " + token()}, timeout=60, **kwargs
    )
    if response.status_code >= 400:
        print(f"{method} {path} failed with HTTP {response.status_code}:")
        print(response.text[:2000])
        sys.exit(1)
    return response.json() if response.text else {}


def main():
    found = call("GET", "/bundleIds", params={"filter[identifier]": BUNDLE_ID, "limit": 50})
    matches = [item for item in found.get("data", []) if item["attributes"]["identifier"] == BUNDLE_ID]
    if not matches:
        print(f"No App ID {BUNDLE_ID} found for this team.")
        sys.exit(1)
    bundle = matches[0]["id"]
    print(f"App ID {BUNDLE_ID} found.")

    current = call("GET", f"/bundleIds/{bundle}/bundleIdCapabilities", params={"limit": 200})
    types = sorted(item["attributes"]["capabilityType"] for item in current.get("data", []))
    print("Capabilities before: " + ", ".join(types))
    if "ICLOUD" in types:
        print("iCloud is already on. Nothing to change.")
        return

    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {
                "capabilityType": "ICLOUD",
                "settings": [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}],
            },
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle}}},
        }
    }
    response = requests.post(
        API + "/bundleIdCapabilities",
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
        data=json.dumps(body),
        timeout=60,
    )
    if response.status_code >= 400:
        print(f"Turning on iCloud failed with HTTP {response.status_code}:")
        print(response.text[:2000])
        sys.exit(1)
    after = call("GET", f"/bundleIds/{bundle}/bundleIdCapabilities", params={"limit": 200})
    print("Capabilities after: " + ", ".join(sorted(i["attributes"]["capabilityType"] for i in after.get("data", []))))
    print("iCloud is now on for " + BUNDLE_ID + ".")


if __name__ == "__main__":
    main()
