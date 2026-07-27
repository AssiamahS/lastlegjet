#!/usr/bin/env python3
"""Pull live empty legs from the Limitless Sky public RSS feed into legs.json.

Feed is free to syndicate with attribution: https://thelimitlesssky.com/empty-legs
Run by .github/workflows/legs.yml on a cron; the landing page fetches legs.json.
"""
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

FEED = "https://thelimitlesssky.com/api/public/empty-legs/rss.xml"
OUT = "legs.json"
MAX_LEGS = 12

TITLE_RE = re.compile(r"^(?P<from_city>.+?) \((?P<from>[A-Z0-9]{3,4})\) → (?P<to_city>.+?) \((?P<to>[A-Z0-9]{3,4})\) · (?P<price>.+)$")
OPERATOR_RE = re.compile(r"Operated by ([^.]+)\.")
SEATS = {"Light": 6, "Midsize": 7, "Super Midsize": 8, "Heavy": 10, "Ultra Long Range": 12, "Turboprop": 6, "VLJ": 4}


def main():
    req = urllib.request.Request(FEED, headers={"User-Agent": "LastLeg/1.0 (+https://assiamahs.github.io/lastlegjet)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        root = ET.fromstring(r.read())

    legs = []
    for item in root.iter("item"):
        title = item.findtext("title", "")
        m = TITLE_RE.match(title.strip())
        if not m:
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
    return 0 if legs else 1


if __name__ == "__main__":
    sys.exit(main())
