"""
"Buy tickets" link builder.

Fandango is the only provider for now: it covers AMC / Regal / Cinemark, its
search URL needs nothing but a title (no per-movie id mapping), and its
affiliate program runs through CJ, whose deep links can wrap any Fandango URL.

Affiliate wrapping is env-driven so links work before the CJ account is
approved — without a template the plain Fandango URL is returned.

  TICKETS_AFFILIATE_TEMPLATE   CJ deep link with a {url} placeholder, e.g.
      https://www.anrdoezrs.net/click-<PID>-<AID>?url={url}
"""

from __future__ import annotations

import os
from urllib.parse import quote, quote_plus

FANDANGO_SEARCH = "https://www.fandango.com/search?q={q}&mode=general"


def _affiliate_template() -> str:
    """Read at call time so changing the env var doesn't require restart."""
    return os.environ.get("TICKETS_AFFILIATE_TEMPLATE", "").strip()


def ticket_link(title: str) -> dict:
    """Build the Fandango ticket link for a movie title.

    Args:
        title: Movie title to search showtimes for.

    Returns:
        {"provider", "url", "affiliate"} — affiliate is False when no
        TICKETS_AFFILIATE_TEMPLATE is configured.
    """
    target = FANDANGO_SEARCH.format(q=quote_plus(title))
    template = _affiliate_template()
    if "{url}" not in template:
        return {"provider": "fandango", "url": target, "affiliate": False}
    return {
        "provider":  "fandango",
        "url":       template.replace("{url}", quote(target, safe="")),
        "affiliate": True,
    }
