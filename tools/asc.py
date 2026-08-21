"""Minimal App Store Connect API client.

Signs its own ES256 JWT with openssl rather than pulling in PyJWT and
cryptography. That is not thrift -- it is so this script keeps working on a
clean machine with nothing but a system python, which is the state the build
box is usually in.

The key itself never appears in this file. It is read from
~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8, the location Apple's own
tools use, and both the key id and issuer id come from the environment:

    export ASC_KEY_ID=...
    export ASC_ISSUER_ID=...
"""

import base64
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"

KEY_ID = os.environ.get("ASC_KEY_ID", "")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "")
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")


def _b64(raw: bytes) -> str:
	return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _der_to_raw(der: bytes) -> bytes:
	"""ECDSA signatures come out of openssl as DER; JWS wants raw r||s.

	Both integers are big-endian, may carry a leading zero byte openssl adds to
	keep them positive, and must be left-padded to exactly 32 bytes for P-256.
	"""
	assert der[0] == 0x30, "not a DER sequence"
	i = 2 if der[1] < 0x80 else 3 + (der[1] & 0x7F) - 1
	out = b""
	for _ in range(2):
		assert der[i] == 0x02, "expected DER integer"
		length = der[i + 1]
		val = der[i + 2 : i + 2 + length].lstrip(b"\x00")
		out += val.rjust(32, b"\x00")
		i += 2 + length
	return out


def token() -> str:
	if not KEY_ID or not ISSUER_ID:
		raise SystemExit("set ASC_KEY_ID and ASC_ISSUER_ID")
	if not os.path.exists(KEY_PATH):
		raise SystemExit(f"no private key at {KEY_PATH}")
	header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
	# 20 minutes is Apple's maximum; anything longer is rejected outright.
	now = int(time.time())
	payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
	signing_input = f"{_b64(json.dumps(header).encode())}.{_b64(json.dumps(payload).encode())}"
	der = subprocess.run(
		["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
		input=signing_input.encode(), capture_output=True, check=True,
	).stdout
	return f"{signing_input}.{_b64(_der_to_raw(der))}"


def call(method: str, path: str, body=None, **params):
	url = path if path.startswith("http") else API + path
	if params:
		url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
	data = json.dumps(body).encode() if body is not None else None
	# Setting up 25 products takes upwards of a hundred requests, and Apple
	# drops a connection now and then; without this a single reset throws away
	# the whole run. Only transport failures and Apple's own "try again" codes
	# are retried -- a 400 means the request is wrong and repeating it is noise.
	for attempt in range(5):
		req = urllib.request.Request(url, data=data, method=method)
		req.add_header("Authorization", "Bearer " + token())
		req.add_header("Content-Type", "application/json")
		try:
			with urllib.request.urlopen(req, timeout=60) as r:
				raw = r.read()
				return json.loads(raw) if raw else {}
		except urllib.error.HTTPError as e:
			if e.code in (429, 500, 502, 503, 504) and attempt < 4:
				time.sleep(2 ** attempt)
				continue
			detail = e.read().decode()
			try:
				errors = json.loads(detail).get("errors", [])
				detail = "\n".join(f"  {x.get('title')}: {x.get('detail')}" for x in errors) or detail
			except Exception:
				pass
			raise SystemExit(f"{method} {url}\nHTTP {e.code}\n{detail}")
		except (urllib.error.URLError, TimeoutError, ConnectionError):
			if attempt == 4:
				raise
			time.sleep(2 ** attempt)


def paged(path: str, **params):
	"""Apple caps a page at 200; follow next links until they run out."""
	out = []
	page = call("GET", path, None, limit=200, **params)
	while True:
		out += page.get("data", [])
		nxt = page.get("links", {}).get("next")
		if not nxt:
			return out
		page = call("GET", nxt)


import urllib.parse  # noqa: E402  (used by call(); kept here to stay stdlib-obvious)
