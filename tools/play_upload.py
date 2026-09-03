"""Upload an .aab to a Google Play track.

The Android half of what ship.sh's sibling comment calls "upload is deliberately
not scripted". It stayed unscripted because there was no Play account; now there
is one, and the manual step is the only thing left standing between a build and
its testers.

    python3 tools/play_upload.py                     # dry run: auth, then say what it would do
    python3 tools/play_upload.py --apply             # actually upload and commit
    python3 tools/play_upload.py --track internal --apply

CREDENTIALS. A Google Cloud service account with a JSON key, granted access in
Play Console under Users and permissions. Point at it with:

    export PLAY_SERVICE_ACCOUNT=~/.playconsole/loot-lagoon-publisher.json

It signs its own RS256 JWT with openssl, deliberately, for the same reason
tools/asc.py does: no PyJWT, no google-api-python-client, nothing to install on
a clean machine with only a system python.

WHY THE DRY RUN IS THE DEFAULT. Committing an edit publishes to the track, and
on a closed track that means real testers get it. A version code can also never
be reused, so an upload aimed at the wrong track costs a rebuild. The dry run
authenticates for real and resolves the bundle, so it catches every credential
and permission problem without changing anything.
"""

import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

PACKAGE = "com.guymaslawi.lootlagoon"
AAB = "build/android-release/LootLagoon.aab"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3"
UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def token(sa: dict) -> str:
    """A service-account assertion, exchanged for an access token."""
    now = int(time.time())
    header = {"alg": "RS256", "typ": "JWT"}
    claims = {
        "iss": sa["client_email"],
        "scope": SCOPE,
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now,
        # Ten minutes. Google caps the assertion at one hour and there is no
        # reason to hold one longer than a single upload.
        "exp": now + 600,
    }
    signing_input = f"{_b64(json.dumps(header).encode())}.{_b64(json.dumps(claims).encode())}"

    # The key never touches disk in plaintext beyond this temp file, which is
    # 600 and removed immediately -- openssl will not take a key on stdin while
    # also reading the payload there.
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as f:
        os.chmod(f.name, 0o600)
        f.write(sa["private_key"])
        key_path = f.name
    try:
        sig = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=signing_input.encode(), capture_output=True, check=True).stdout
    finally:
        os.unlink(key_path)

    assertion = f"{signing_input}.{_b64(sig)}"
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion,
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["access_token"]


def call(method: str, url: str, tok: str, body=None, raw=None, content_type=None):
    headers = {"Authorization": "Bearer " + tok}
    data = raw
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            text = r.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:600]
        raise SystemExit(f"!! {method} {url}\n   HTTP {e.code}: {detail}")


def main() -> None:
    args = sys.argv[1:]
    apply = "--apply" in args
    track = "alpha"
    if "--track" in args:
        track = args[args.index("--track") + 1]

    path = os.environ.get("PLAY_SERVICE_ACCOUNT", "")
    if not path or not os.path.exists(os.path.expanduser(path)):
        raise SystemExit(
            "no service account. Create one in Google Cloud, grant it in Play Console\n"
            "under Users and permissions, then:\n"
            "    export PLAY_SERVICE_ACCOUNT=~/.playconsole/loot-lagoon-publisher.json")
    sa = json.load(open(os.path.expanduser(path)))

    if not os.path.exists(AAB):
        raise SystemExit(f"no bundle at {AAB} -- run ./ship_android.sh first")
    size = os.path.getsize(AAB)

    print(f"==> authenticating as {sa['client_email']}")
    tok = token(sa)

    # Proves the grant is real before anything is created. A service account
    # that authenticates but was never invited in Play Console fails here, and
    # that is by far the most common way this is misconfigured.
    print("==> opening an edit")
    edit = call("POST", f"{API}/applications/{PACKAGE}/edits", tok, body={})
    edit_id = edit["id"]
    print(f"    edit {edit_id}")

    if not apply:
        print(f"\nDRY RUN. Would upload {AAB} ({size/1e6:.0f}MB) to track '{track}'")
        print("Credentials and permissions are good -- re-run with --apply to do it.")
        call("DELETE", f"{API}/applications/{PACKAGE}/edits/{edit_id}", tok)
        print("    edit discarded, nothing changed")
        return

    print(f"==> uploading {size/1e6:.0f}MB")
    with open(AAB, "rb") as f:
        bundle = call("POST",
                      f"{UPLOAD}/applications/{PACKAGE}/edits/{edit_id}/bundles?uploadType=media",
                      tok, raw=f.read(), content_type="application/octet-stream")
    code = bundle["versionCode"]
    print(f"    accepted as version code {code}")

    # What is on the track right now, read before we overwrite it. This line
    # used to be a hardcoded "62 stays live", written the day the script was and
    # a lie on every run after -- which is exactly the stale-build-number
    # confusion this project has already paid for once.
    was = []
    for tr in call("GET", f"{API}/applications/{PACKAGE}/edits/{edit_id}/tracks",
                   tok).get("tracks", []):
        if tr.get("track") == track:
            for r in tr.get("releases", []):
                was += r.get("versionCodes", []) or []

    print(f"==> assigning to track '{track}'")
    call("PUT", f"{API}/applications/{PACKAGE}/edits/{edit_id}/tracks/{track}", tok, body={
        "track": track,
        "releases": [{"versionCodes": [str(code)], "status": "completed"}],
    })

    print("==> committing")
    call("POST", f"{API}/applications/{PACKAGE}/edits/{edit_id}:commit", tok)
    print(f"\nDONE. Version code {code} is on '{track}' and now goes through review.")
    if was:
        print(f"{', '.join(was)} stays live for testers until it clears; "
              "the 14-day clock is untouched.")
    else:
        print(f"'{track}' had no release before this one; the 14-day clock is untouched.")


if __name__ == "__main__":
    main()
