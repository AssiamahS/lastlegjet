#!/usr/bin/env python3
"""Pull live empty legs from the Limitless Sky public RSS feed into legs.json.

Feed is free to syndicate with attribution: https://thelimitlesssky.com/empty-legs
Run by .github/workflows/legs.yml on a cron; the landing page fetches legs.json.
"""
import json
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

FEED = "https://thelimitlesssky.com/api/public/empty-legs/rss.xml"
OUT = "legs.json"
MAX_LEGS = 12
FETCH_TRIES = 3
# a board this old is worse than a red run; younger than this, keep serving it
STALE_AFTER_H = 36

TITLE_RE = re.compile(r"^(?P<from_city>.+?) \((?P<from>[A-Z0-9]{3,4})\) → (?P<to_city>.+?) \((?P<to>[A-Z0-9]{3,4})\) · (?P<price>.+)$")
OPERATOR_RE = re.compile(r"Operated by ([^.]+)\.")
SEATS = {"Light": 6, "Midsize": 7, "Super Midsize": 8, "Heavy": 10, "Ultra Long Range": 12, "Turboprop": 6, "VLJ": 4}


def fetch_feed():
    """Feed bytes, retried — the source 5xx's / serves an empty channel now and then."""
    req = urllib.request.Request(FEED, headers={"User-Agent": "LastLeg/1.0 (+https://assiamahs.github.io/lastlegjet)"})
    last = None
    for attempt in range(1, FETCH_TRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read()
            if b"<item>" in body:
                return body
            last = "feed returned no items"
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last = str(e)
        print(f"attempt {attempt}/{FETCH_TRIES}: {last}")
        if attempt < FETCH_TRIES:
            time.sleep(20 * attempt)
    return None


def board_age_hours():
    """Hours since the committed legs.json was written, or None if unreadable/empty."""
    try:
        with open(OUT) as f:
            old = json.load(f)
        if not old.get("legs"):
            return None
        then = datetime.strptime(old["updated"], "%Y-%m-%dT%H:%MZ").replace(tzinfo=timezone.utc)
    except (OSError, ValueError, KeyError):
        return None
    return (datetime.now(timezone.utc) - then).total_seconds() / 3600


def keep_old_board(reason):
    """No usable legs this run: leave legs.json alone, only go red once it is stale."""
    age = board_age_hours()
    if age is not None and age < STALE_AFTER_H:
        print(f"::warning::{reason} - keeping existing board ({age:.0f}h old)")
        return 0
    print(f"::error::{reason} and existing board is stale or missing")
    return 1


def main():
    body = fetch_feed()
    if body is None:
        return keep_old_board("feed unreachable or empty")
    try:
        root = ET.fromstring(body)
    except ET.ParseError as e:
        return keep_old_board(f"feed is not valid xml ({e})")

    seen = unmatched = past = 0
    legs = []
    for item in root.iter("item"):
        seen += 1
        title = item.findtext("title", "")
        m = TITLE_RE.match(title.strip())
        if not m:
            unmatched += 1
            continue
        desc = item.findtext("description", "")
        cats = [c.text for c in item.findall("category") if c.text]
        aircraft = cats[0] if cats else "Private jet"
        category = next((c for c in cats[1:] if c in SEATS), "")
        op = OPERATOR_RE.search(desc)
        pub = item.findtext("pubDate", "")
        try:
            dt = parsedate_to_datetime(pub)
        except (TypeError, ValueError):
            continue
        if dt < datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0):
            past += 1
            continue
        legs.append({
            "id": item.findtext("guid", ""),
            "date": dt.strftime("%b %d"),
            "sort": dt.isoformat(),
            "from": m["from"], "to": m["to"],
            "from_city": m["from_city"], "to_city": m["to_city"],
            "aircraft": aircraft,
            "category": category,
            "seats": SEATS.get(category, 6),
            "operator": op.group(1) if op else "",
            "price": m["price"].strip(),
        })

    print(f"feed: {seen} items, {unmatched} unparsed titles, {past} already departed, {len(legs)} usable")
    if not legs:
        return keep_old_board("feed had no usable legs")

    # priced legs first, then soonest departures
    legs.sort(key=lambda l: (l["price"].lower() == "on request", l["sort"]))
    legs = legs[:MAX_LEGS]
    legs.sort(key=lambda l: l["sort"])

    payload = {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ"),
        "source": "Limitless Sky",
        "source_url": "https://thelimitlesssky.com/empty-legs",
        "legs": legs,
    }
    with open(OUT, "w") as f:
        json.dump(payload, f, indent=1)
    print(f"wrote {len(legs)} legs to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
