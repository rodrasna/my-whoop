"""SugarWOD web-session client (email/password login, athlete API)."""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from typing import Any

import httpx

_BASE = "https://app.sugarwod.com"
_CSRF_RE = re.compile(r"var\s+CSRF\s*=\s*'([^']+)'")
_ATHLETE_ID_RE = re.compile(r"var\s+CUR_ATH_ID\s*=\s*'([^']+)'")


class SugarWODError(RuntimeError):
    pass


@dataclass
class SugarWODClient:
    email: str
    password: str
    track_name: str = "PRVN Español"
    _client: httpx.Client | None = None
    athlete_id: str | None = None
    track_key: str | None = None
    _tracks_cache: list[dict[str, Any]] = field(default_factory=list, repr=False)

    @classmethod
    def from_env(cls) -> SugarWODClient | None:
        email = os.environ.get("SUGARWOD_EMAIL", "").strip()
        password = os.environ.get("SUGARWOD_PASSWORD", "").strip()
        if not email or not password:
            return None
        track = os.environ.get("SUGARWOD_TRACK", "PRVN Español").strip() or "PRVN Español"
        return cls(email=email, password=password, track_name=track)

    def __enter__(self) -> SugarWODClient:
        self._client = httpx.Client(
            base_url=_BASE,
            timeout=45.0,
            follow_redirects=True,
            headers={
                "User-Agent": "OpenWhoop/1.0",
                "Accept": "application/json",
            },
        )
        return self

    def __exit__(self, *_) -> None:
        if self._client:
            self._client.close()
            self._client = None

    @property
    def http(self) -> httpx.Client:
        if not self._client:
            raise SugarWODError("client not started; use `with SugarWODClient(...) as c:`")
        return self._client

    def login(self) -> None:
        page = self.http.get("/login")
        page.raise_for_status()
        m = _CSRF_RE.search(page.text)
        if not m:
            raise SugarWODError("CSRF token not found on login page")
        resp = self.http.post(
            "/public/api/v1/login",
            json={
                "username": self.email.strip().lower(),
                "password": self.password,
                "_csrf": m.group(1),
            },
            headers={
                "Content-Type": "application/json",
                "Referer": f"{_BASE}/login",
                "Origin": _BASE,
            },
        )
        if resp.status_code >= 400:
            raise SugarWODError(f"login HTTP {resp.status_code}")
        body = resp.json()
        if not body.get("success"):
            raise SugarWODError(body.get("message") or "login failed")
        self._load_athlete_id()
        self.track_key = self._resolve_track_key()

    def _load_athlete_id(self) -> None:
        for path in ("/home", "/workouts/calendar"):
            page = self.http.get(path)
            page.raise_for_status()
            m = _ATHLETE_ID_RE.search(page.text)
            if m:
                self.athlete_id = m.group(1)
                return
        raise SugarWODError("athlete id not found after login")

    def _resolve_track_key(self) -> str:
        tracks = self.fetch_affiliate_tracks()
        want = _norm_track(self.track_name)
        for track in tracks:
            for field in ("key", "name"):
                val = track.get(field)
                if isinstance(val, str) and _norm_track(val) == want:
                    return track["key"]
        for track in tracks:
            name = str(track.get("name") or "")
            key = str(track.get("key") or "")
            if want in _norm_track(name) or want in _norm_track(key):
                return track["key"]
        raise SugarWODError(f"track not found: {self.track_name!r}")

    def fetch_affiliate_tracks(self) -> list[dict[str, Any]]:
        if self._tracks_cache:
            return self._tracks_cache
        resp = self.http.get("/api/affiliates/tracks")
        resp.raise_for_status()
        body = resp.json()
        if not body.get("success"):
            raise SugarWODError(body.get("message") or "tracks fetch failed")
        data = body.get("data") or []
        self._tracks_cache = data if isinstance(data, list) else []
        return self._tracks_cache

    def fetch_workouts_week(self, week_monday_yyyymmdd: str) -> list[dict[str, Any]]:
        if not self.track_key:
            raise SugarWODError("not logged in")
        resp = self.http.get(
            "/api/workouts",
            params={"week": week_monday_yyyymmdd, "track": self.track_key},
        )
        if resp.status_code == 401:
            raise SugarWODError("session expired")
        resp.raise_for_status()
        body = resp.json()
        if not body.get("success"):
            raise SugarWODError(body.get("message") or "workouts fetch failed")
        data = body.get("data")
        return data if isinstance(data, list) else []


def _norm_track(value: str) -> str:
    return (
        value.strip()
        .upper()
        .replace("Ñ", "N")
        .replace("Á", "A")
        .replace("É", "E")
        .replace("Í", "I")
        .replace("Ó", "O")
        .replace("Ú", "U")
    )
