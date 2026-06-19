"""Tests for subjective morning sleep check-ins."""
from __future__ import annotations

import importlib
import time

import psycopg
import pytest

from tests.conftest import requires_docker
from app import read as _read, store


@pytest.fixture
def client(clean_db, tmp_path, monkeypatch):
    monkeypatch.setenv("WHOOP_API_KEY", "secret")
    monkeypatch.setenv("WHOOP_DB_DSN", clean_db)
    monkeypatch.setenv("WHOOP_RAW_ROOT", str(tmp_path))
    import app.main as m
    importlib.reload(m)
    from fastapi.testclient import TestClient
    return TestClient(m.app, headers={"Authorization": "Bearer secret"})


@requires_docker
def test_post_and_get_sleep_check_in(client, clean_db):
    saved = time.time()
    body = {
        "device": "devCI",
        "day_key": "2026-06-18",
        "morning_feeling": 4,
        "onset": "hard",
        "factors": ["heat", "feelRecovered"],
        "note": "ventilador",
        "saved_at": saved,
        "recovery_pct": 0.62,
        "sleep_efficiency_pct": 88.0,
    }
    r = client.post("/v1/sleep-check-in", json=body)
    assert r.status_code == 200
    data = r.json()
    assert data["day_key"] == "2026-06-18"
    assert data["morning_feeling"] == 4
    assert "heat" in data["factors"]

    r2 = client.get("/v1/sleep-check-ins", params={
        "device": "devCI", "from": "2026-06-01", "to": "2026-06-30",
    })
    assert r2.status_code == 200
    assert len(r2.json()) == 1


@requires_docker
def test_post_sleep_check_in_invalid_onset_422(client):
    body = {
        "device": "devCI2",
        "day_key": "2026-06-18",
        "morning_feeling": 3,
        "onset": "impossible",
        "saved_at": time.time(),
    }
    r = client.post("/v1/sleep-check-in", json=body)
    assert r.status_code == 422


@requires_docker
def test_upsert_sleep_check_in_idempotent(clean_db):
    with psycopg.connect(clean_db) as conn:
        store.ensure_device(conn, "devCI3")
        row = {
            "day_key": "2026-06-17",
            "morning_feeling": 2,
            "onset": "normal",
            "factors": ["noise"],
            "note": None,
            "saved_at": time.time(),
            "recovery_pct": 0.4,
            "sleep_efficiency_pct": 70.0,
        }
        store.upsert_sleep_check_in(conn, "devCI3", row)
        row["morning_feeling"] = 5
        store.upsert_sleep_check_in(conn, "devCI3", row)
        conn.commit()
        rows = _read.query_sleep_check_ins(conn, "devCI3", "2026-06-01", "2026-06-30")
    assert len(rows) == 1
    assert rows[0]["morning_feeling"] == 5
