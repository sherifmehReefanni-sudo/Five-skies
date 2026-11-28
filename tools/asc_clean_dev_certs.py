"""Revokes the Apple Development certificates that earlier CI runs left behind.

Every TestFlight run signs on a fresh GitHub Mac, and Xcode asks Apple for a new
development certificate there. Its private key is thrown away with the Mac, so the
certificate is useless afterwards, but it still counts toward Apple's limit. Reef
approved (Nov 28, 2026) clearing them before each build.

Only development certificates whose name says "Created via API" are touched: those are
the ones the build machine made with the App Store Connect key. Distribution
certificates and any certificate made by hand are never touched. Reads ASC_KEY_ID,
ASC_ISSUER_ID and ASC_KEY_PATH from the environment, never prints the key, and prints
counts only."""
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
DEVELOPMENT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}
MARKER = "created via api"


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


def headers():
    return {"Authorization": "Bearer " + token()}


def list_certificates():
    found = []
    url = API + "/certificates"
    params = {"limit": 200, "fields[certificates]": "name,displayName,certificateType"}
    while url:
        response = requests.get(url, headers=headers(), params=params, timeout=60)
        if response.status_code >= 400:
            print(f"Listing certificates failed with HTTP {response.status_code}.")
            print(response.text[:1000])
            sys.exit(1)
        body = response.json()
        found.extend(body.get("data", []))
        url = body.get("links", {}).get("next")
        params = None
    return found


def is_ci_development(cert):
    attributes = cert.get("attributes", {})
    kind = attributes.get("certificateType", "")
    names = " ".join(str(attributes.get(field) or "") for field in ("name", "displayName")).lower()
    return kind in DEVELOPMENT_TYPES and MARKER in names


def main():
    certificates = list_certificates()
    development = [c for c in certificates if c.get("attributes", {}).get("certificateType") in DEVELOPMENT_TYPES]
    targets = [c for c in certificates if is_ci_development(c)]
    print(f"Certificates on the team: {len(certificates)}, development: {len(development)}, made by CI: {len(targets)}.")

    revoked = 0
    for cert in targets:
        response = requests.delete(API + "/certificates/" + cert["id"], headers=headers(), timeout=60)
        if response.status_code in (200, 204):
            revoked += 1
        else:
            print(f"One certificate could not be revoked (HTTP {response.status_code}).")
    print(f"Revoked {revoked} of {len(targets)} CI development certificates. Nothing else was changed.")
    if targets and revoked == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
