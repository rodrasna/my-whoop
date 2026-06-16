"""PRVN week sync orchestration + on-disk cache."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from .client import SugarWODClient, SugarWODError
from .sync import fetch_prvn_week_text, monday_key_for, week_to_program_dict


def cache_path(raw_root: str, device_id: str) -> Path:
    return Path(raw_root) / "prvn" / f"{device_id}.json"


def load_cached(raw_root: str, device_id: str) -> dict[str, Any] | None:
    path = cache_path(raw_root, device_id)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def save_cached(raw_root: str, device_id: str, payload: dict[str, Any]) -> None:
    path = cache_path(raw_root, device_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2))


def sync_week(
    *,
    raw_root: str,
    device_id: str,
    week_monday_yyyymmdd: str | None = None,
) -> dict[str, Any]:
    client_cfg = SugarWODClient.from_env()
    if not client_cfg:
        raise SugarWODError("SUGARWOD_EMAIL / SUGARWOD_PASSWORD not configured on server")

    week = week_monday_yyyymmdd or monday_key_for()
    with client_cfg as client:
        client.login()
        text = fetch_prvn_week_text(week, client)
        if not text:
            raise SugarWODError(f"no workouts returned for week {week}")
        payload = week_to_program_dict(week, text, client.track_name)
        payload["deviceId"] = device_id
        payload["trackKey"] = client.track_key
        save_cached(raw_root, device_id, payload)
        return payload


def sugarwod_configured() -> bool:
    return SugarWODClient.from_env() is not None
