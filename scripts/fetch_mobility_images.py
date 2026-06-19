#!/usr/bin/env python3
"""Download mobility exercise images from YouTube thumbnails in mobility_catalog.json."""
from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "ios/OpenWhoop/Mobility/mobility_catalog.json"
OUT = ROOT / "ios/OpenWhoop/Mobility/ExerciseImages"

YT_ID_RE = re.compile(
    r"(?:youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]{6,})"
)


def youtube_id(url: str) -> str | None:
    m = YT_ID_RE.search(url)
    return m.group(1) if m else None


def thumb_url(video_id: str) -> str:
    return f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"


def main() -> int:
    if not CATALOG.is_file():
        print(f"Catalog not found: {CATALOG}", file=sys.stderr)
        return 1
    exercises = json.loads(CATALOG.read_text(encoding="utf-8"))["exercises"]
    OUT.mkdir(parents=True, exist_ok=True)
    ok, skip, fail = 0, 0, 0
    for ex in exercises:
        eid = ex["id"]
        dest = OUT / f"{eid}.jpg"
        if dest.is_file() and dest.stat().st_size > 2000:
            skip += 1
            continue
        vid = youtube_id(ex.get("youtube_url", ""))
        if not vid:
            print(f"  skip (no video id): {eid}")
            skip += 1
            continue
        url = thumb_url(vid)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "OpenWhoop-mobility-fetch/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            if len(data) < 1000:
                raise ValueError(f"response too small ({len(data)} bytes)")
            dest.write_bytes(data)
            print(f"  ok: {eid}")
            ok += 1
        except Exception as exc:
            print(f"  fail: {eid} — {exc}", file=sys.stderr)
            fail += 1
    print(f"Done: {ok} downloaded, {skip} skipped, {fail} failed → {OUT}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
