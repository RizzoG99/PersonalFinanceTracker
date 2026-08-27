#!/usr/bin/env python3
"""Assign a just-uploaded TestFlight build to a Beta Group via the App Store
Connect API. Called by `scripts/xcb assign-testers <group>`; not meant to be
run standalone. Uses only stdlib + `cryptography` (already installed) — no
PyJWT/requests needed for one JWT and a handful of REST calls.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def find_key_path(key_id: str) -> str:
    for pattern in (
        os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8"),
        f"private_keys/AuthKey_{key_id}.p8",
    ):
        if os.path.exists(pattern):
            return pattern
    sys.exit(
        f"asc_api: no AuthKey_{key_id}.p8 in ~/.appstoreconnect/private_keys or ./private_keys"
    )


def make_jwt(key_id: str, issuer_id: str) -> str:
    key_path = find_key_path(key_id)
    with open(key_path, "rb") as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)

    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "exp": int(time.time()) + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"

    der_sig = private_key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der_sig)
    # JWS ES256 wants raw r||s, each 32 bytes for P-256 — not the DER openssl/cryptography give by default.
    raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{signing_input}.{b64url(raw_sig)}"


def call(path: str, token: str, method: str = "GET", body: dict | None = None) -> dict:
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"asc_api: {method} {url} -> {e.code} {e.read().decode()}")


def find_app_id(bundle_id: str, token: str) -> str:
    r = call(f"/apps?filter[bundleId]={bundle_id}", token)
    if not r["data"]:
        sys.exit(f"asc_api: no app found for bundle id {bundle_id}")
    return r["data"][0]["id"]


def find_beta_group(app_id: str, name: str, token: str) -> tuple[str, bool]:
    r = call(f"/betaGroups?filter[app]={app_id}&filter[name]={urllib.parse.quote(name)}", token)
    if not r["data"]:
        sys.exit(f"asc_api: no beta group named {name!r} on this app")
    group = r["data"][0]
    return group["id"], group["attributes"]["isInternalGroup"]


def set_whats_new(build_id: str, notes: str, token: str) -> None:
    """Create or update the en-US 'What to Test' text for a build."""
    r = call(f"/betaBuildLocalizations?filter[build]={build_id}&filter[locale]=en-US", token)
    if r["data"]:
        loc_id = r["data"][0]["id"]
        call(
            f"/betaBuildLocalizations/{loc_id}",
            token,
            method="PATCH",
            body={
                "data": {
                    "type": "betaBuildLocalizations",
                    "id": loc_id,
                    "attributes": {"whatsNew": notes},
                }
            },
        )
    else:
        call(
            "/betaBuildLocalizations",
            token,
            method="POST",
            body={
                "data": {
                    "type": "betaBuildLocalizations",
                    "attributes": {"locale": "en-US", "whatsNew": notes},
                    "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
                }
            },
        )


def wait_for_build(app_id: str, version: str, build_number: str, token: str, timeout_s: int) -> str:
    """Builds take a while to finish Apple's processing before they're assignable."""
    deadline = time.time() + timeout_s
    path = (
        f"/builds?filter[app]={app_id}&filter[version]={build_number}"
        f"&filter[preReleaseVersion.version]={version}&limit=1"
    )
    while True:
        r = call(path, token)
        if r["data"]:
            build = r["data"][0]
            state = build["attributes"]["processingState"]
            if state == "VALID":
                return build["id"]
            if state == "FAILED" or state == "INVALID":
                sys.exit(f"asc_api: build {version} ({build_number}) processing state is {state}")
            print(f"asc_api: build {version} ({build_number}) still {state}, waiting...")
        else:
            print(f"asc_api: build {version} ({build_number}) not visible yet, waiting...")
        if time.time() > deadline:
            sys.exit(f"asc_api: timed out waiting for build {version} ({build_number}) to finish processing")
        time.sleep(30)


def main():
    mode = sys.argv[1]
    key_id = os.environ["ASC_KEY_ID"]
    issuer_id = os.environ["ASC_ISSUER_ID"]
    timeout_s = int(os.environ.get("ASC_WAIT_TIMEOUT", "1800"))
    token = make_jwt(key_id, issuer_id)

    if mode == "release-notes":
        bundle_id, version, build_number = sys.argv[2:5]
        notes = sys.stdin.read().strip()
        app_id = find_app_id(bundle_id, token)
        build_id = wait_for_build(app_id, version, build_number, token, timeout_s)
        set_whats_new(build_id, notes, token)
        print(f"asc_api: set What to Test for build {version} ({build_number})")
        return

    if mode == "assign-testers":
        bundle_id, version, build_number, group_name = sys.argv[2:6]
        app_id = find_app_id(bundle_id, token)
        group_id, is_internal = find_beta_group(app_id, group_name, token)

        if is_internal:
            # Internal groups auto-receive every processed build — there's no
            # relationship to assign; App Store Connect rejects the attempt (422).
            # Still worth waiting so the run reports the build as actually ready.
            wait_for_build(app_id, version, build_number, token, timeout_s)
            print(
                f"asc_api: {group_name!r} is an internal group — it already has every "
                f"processed build automatically, including {version} ({build_number})"
            )
            return

        build_id = wait_for_build(app_id, version, build_number, token, timeout_s)
        call(
            f"/betaGroups/{group_id}/relationships/builds",
            token,
            method="POST",
            body={"data": [{"type": "builds", "id": build_id}]},
        )
        print(f"asc_api: build {version} ({build_number}) assigned to beta group {group_name!r}")
        return

    sys.exit(f"asc_api: unknown mode {mode!r} (want release-notes | assign-testers)")


if __name__ == "__main__":
    main()
