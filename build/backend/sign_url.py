#!/usr/bin/env python3
"""Mint an HMAC pre-signed URL for the Records API.

Reads the signing key from RECORDS_SIGNING_KEY, falling back to AGENT_API_TOKEN
— set one in your shell first. Examples:

    # Whole API, never expires — append the printed query string to any /v0 path:
    python sign_url.py --scope /v0

    # One table, full URL, expires in 7 days:
    python sign_url.py --scope /v0/app1/Contacts \\
        --base https://rated-api.onrender.com --ttl 604800
"""
import argparse
import time

import presign


def main() -> None:
    p = argparse.ArgumentParser(description="Mint a pre-signed Records URL")
    p.add_argument("--scope", required=True,
                   help='Path prefix to authorize, e.g. "/v0" or "/v0/app1/Contacts"')
    p.add_argument("--base", default="",
                   help="Base URL, e.g. https://rated-api.onrender.com (for a full example URL)")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--exp", type=int, help="Absolute unix expiry timestamp (0 = never)")
    g.add_argument("--ttl", type=int, help="Seconds from now until expiry")
    args = p.parse_args()

    if not presign.signing_key():
        raise SystemExit("No signing key — set RECORDS_SIGNING_KEY or AGENT_API_TOKEN.")

    if args.ttl is not None:
        exp = int(time.time()) + args.ttl
    elif args.exp is not None:
        exp = args.exp
    else:
        exp = 0  # never expires

    print("query params:  " + presign.query_string(args.scope, exp))
    print("expires:       " + ("never" if exp == 0 else time.strftime(
        "%Y-%m-%d %H:%M:%SZ", time.gmtime(exp))))
    if args.base:
        print("example URL:   " + presign.mint(args.base, args.scope, exp))


if __name__ == "__main__":
    main()
