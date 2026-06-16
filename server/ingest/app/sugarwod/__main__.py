"""CLI probe for SugarWOD sync (uses server/.env when present)."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

from .client import SugarWODClient, SugarWODError
from .sync import fetch_prvn_week_text


def _load_env() -> None:
    env_path = Path(__file__).resolve().parents[3] / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        if not key.startswith("SUGARWOD_"):
            continue
        val = val.strip().strip('"').strip("'")
        os.environ.setdefault(key, val)


def monday_key(d: dt.date | None = None) -> str:
    day = d or dt.date.today()
    monday = day - dt.timedelta(days=day.weekday())
    return monday.strftime("%Y%m%d")


def main(argv: list[str] | None = None) -> int:
    _load_env()
    p = argparse.ArgumentParser(description="Probe SugarWOD PRVN sync")
    p.add_argument("--week", default=monday_key(), help="Monday YYYYMMDD")
    p.add_argument("--dump-json", action="store_true", help="Print raw workouts JSON")
    args = p.parse_args(argv)

    client_cfg = SugarWODClient.from_env()
    if not client_cfg:
        print("Missing SUGARWOD_EMAIL / SUGARWOD_PASSWORD in environment", file=sys.stderr)
        return 1

    try:
        with client_cfg as client:
            client.login()
            print(f"login ok · athlete={client.athlete_id}")
            tracks = client.fetch_affiliate_tracks()
            print(f"tracks: {len(tracks)}")
            for t in tracks[:12]:
                name = t.get("name") or t.get("trackName") or t.get("id")
                print(f"  - {name}")
            workouts = client.fetch_workouts_week(args.week)
            print(f"workouts week {args.week}: {len(workouts)}")
            if args.dump_json:
                print(json.dumps(workouts, indent=2, ensure_ascii=False)[:8000])
            text = fetch_prvn_week_text(args.week, client)
            print("--- paste preview ---")
            print(text[:4000] or "(empty)")
    except SugarWODError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
