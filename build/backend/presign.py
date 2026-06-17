"""HMAC pre-signed URLs for the Records API.

A pre-signed URL carries a *signature* in its query string instead of the raw
secret — so it can be shared, bookmarked, or land in an access log without
leaking the signing key, and the holder can't forge a URL for a wider scope.

A URL is authorized by three query params:
    scope  path prefix the signature grants, e.g. "/v0" (whole API) or
           "/v0/app1/Contacts" (one table). Boundary-matched, so "/v0/app1"
           grants "/v0/app1/Contacts" but NOT "/v0/app1xyz".
    exp    unix expiry timestamp; 0 means never expires ("always auth").
    sig    hex HMAC-SHA256 over f"{scope}\\n{exp}".

Revoke every URL minted under a key by rotating the key.

Signing key resolution: a dedicated RECORDS_SIGNING_KEY is preferred so that
rotating signed-URL access never disturbs header/token clients. If it's unset
we fall back to the AGENT_API_TOKEN string so pre-signed URLs work with zero
extra config — but note that with the fallback, the URLs are tied to the exact
AGENT_API_TOKEN value, so editing that token (e.g. adding a comma-separated
one) invalidates them. Set RECORDS_SIGNING_KEY for stable, independently
rotatable URLs.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import time
from urllib.parse import urlencode


def signing_key() -> bytes:
    """The HMAC key, as bytes. Empty when nothing is configured."""
    key = os.environ.get("RECORDS_SIGNING_KEY", "").strip()
    if not key:
        key = os.environ.get("AGENT_API_TOKEN", "").strip()
    return key.encode("utf-8")


def sign(scope: str, exp: int, key: bytes | None = None) -> str:
    """The hex signature for (scope, exp). Reads the env key if none is passed."""
    k = signing_key() if key is None else key
    msg = f"{scope}\n{int(exp)}".encode("utf-8")
    return hmac.new(k, msg, hashlib.sha256).hexdigest()


def path_in_scope(path: str, scope: str) -> bool:
    """True when `path` falls under the `scope` prefix on a path boundary."""
    return path == scope or path.startswith(scope.rstrip("/") + "/")


def verify(path: str, scope: str, exp: int, sig: str, key: bytes | None = None) -> bool:
    """Constant-time check that (scope, exp, sig) authorizes `path`. False on any
    of: missing scope/sig/key, expired, path outside scope, bad signature."""
    if not scope or not sig:
        return False
    k = signing_key() if key is None else key
    if not k:
        return False
    if exp != 0 and time.time() > exp:
        return False
    if not path_in_scope(path, scope):
        return False
    return hmac.compare_digest(sign(scope, exp, k), sig)


def query_string(scope: str, exp: int = 0, key: bytes | None = None) -> str:
    """The `scope=&exp=&sig=` query string to append to any in-scope path."""
    return urlencode({"scope": scope, "exp": int(exp), "sig": sign(scope, exp, key)})


def mint(base_url: str, scope: str, exp: int = 0, key: bytes | None = None) -> str:
    """A full pre-signed URL hitting the `scope` path. For a broad scope (e.g.
    "/v0") append query_string() to a concrete endpoint instead."""
    return f"{base_url.rstrip('/')}{scope}?{query_string(scope, exp, key)}"
