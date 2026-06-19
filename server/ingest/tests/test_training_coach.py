"""Training coach deterministic report (task-09 Phase A)."""
import datetime as _dt
import importlib

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.analysis import training_coach
from app import store
from tests.conftest import requires_docker
from tests.test_daily import _active_block, _epoch, _merge, _still_block

DEVICE = "devCoachR"
DAY = _dt.date(2026, 6, 16)
DAY_KEY = DAY.isoformat()


@pytest.fixture
def client(clean_db, tmp_path, monkeypatch):
    monkeypatch.setenv("WHOOP_API_KEY", "secret")
    monkeypatch.setenv("WHOOP_DB_DSN", clean_db)
    monkeypatch.setenv("WHOOP_RAW_ROOT", str(tmp_path))
    import app.main as m
    importlib.reload(m)
    return TestClient(m.app, headers={"Authorization": "Bearer secret"})


def _seed_day_with_workout(dsn, *, strain_bpm: int = 140):
    prev = DAY - _dt.timedelta(days=1)
    night_start = _epoch(prev, 22, 0)
    night = _merge(
        _active_block(night_start, 20, bpm0=78),
        _still_block(night_start + 20 * 60, 120, bpm=56),
        _still_block(night_start + 140 * 60, 80, bpm=49, dip=True),
        _still_block(night_start + 220 * 60, 150, bpm=55),
        _still_block(night_start + 370 * 60, 60, bpm=52, dip=True),
        _active_block(night_start + 430 * 60, 15, bpm0=80),
    )
    workout = _active_block(_epoch(DAY, 10, 0), 35, bpm0=strain_bpm)
    with psycopg.connect(dsn) as conn:
        store.ensure_device(conn, DEVICE)
        store.upsert_streams(conn, DEVICE, _merge(night, workout))
        from app.analysis import daily
        daily.compute_day(conn, DEVICE, DAY)
        conn.commit()
    with psycopg.connect(dsn) as conn:
        rows = conn.execute(
            "SELECT device_id, start_ts FROM exercise_sessions WHERE device_id=%s "
            "ORDER BY start_ts DESC LIMIT 1",
            (DEVICE,),
        ).fetchone()
    return f"{rows[0]}|{int(rows[1].timestamp())}"


@requires_docker
def test_qualifier_harder_than_baseline(client, clean_db):
    """Classifier day with higher strain than prior qualifier sessions → insight."""
    wid = _seed_day_with_workout(clean_db, strain_bpm=168)
    # Three prior qualifier days with milder workouts.
    for offset in (3, 5, 7):
        d = DAY - _dt.timedelta(days=offset)
        prev = d - _dt.timedelta(days=1)
        night_start = _epoch(prev, 22, 0)
        night = _merge(
            _still_block(night_start + 20 * 60, 400, bpm=55),
        )
        w = _active_block(_epoch(d, 10, 0), 20, bpm0=118)
        with psycopg.connect(clean_db) as conn:
            store.upsert_streams(conn, DEVICE, _merge(night, w))
            from app.analysis import daily
            daily.compute_day(conn, DEVICE, d)
            rows = conn.execute(
                "SELECT start_ts FROM exercise_sessions WHERE device_id=%s "
                "AND start_ts >= %s::date AT TIME ZONE 'UTC' "
                "AND start_ts < (%s::date + INTERVAL '1 day') AT TIME ZONE 'UTC'",
                (DEVICE, d, d),
            ).fetchall()
            pid = f"{DEVICE}|{int(rows[0][0].timestamp())}"
            store.upsert_workout_day_plan(conn, DEVICE, {
                "day_key": d.isoformat(),
                "primary_workout_id": pid,
                "activity_type": "crossfit",
                "crossfit_style": "qualifier",
                "blocks_done": ["metcon"],
                "note": None,
                "saved_at": _epoch(d, 12, 0),
            })
            conn.commit()

    with psycopg.connect(clean_db) as conn:
        store.upsert_workout_day_plan(conn, DEVICE, {
            "day_key": DAY_KEY,
            "primary_workout_id": wid,
            "activity_type": "crossfit",
            "crossfit_style": "qualifier",
            "blocks_done": ["metcon"],
            "note": "Open 26.2",
            "saved_at": _epoch(DAY, 12, 0),
        })
        store.upsert_daily_metrics(conn, DEVICE, DAY, {
            "total_sleep_min": 420,
            "efficiency": 0.9,
            "deep_min": 60,
            "rem_min": 90,
            "light_min": 270,
            "disturbances": 2,
            "resting_hr": 52,
            "avg_hrv": 45,
            "recovery": 40.0,
            "strain": 14.0,
            "exercise_count": 1,
        })
        conn.commit()

    r = client.post("/v1/coach/day", params={"device": DEVICE, "day": DAY_KEY})
    assert r.status_code == 200, r.text
    report = r.json()
    assert report["style"] == "qualifier"
    assert report["summary"]["verdict"] in ("harder_than_usual", "typical")
    assert any(
        i in report["insights"]
        for i in ("strain_above_baseline", "avg_hr_above_baseline", "time_in_zone_4_above_baseline")
    )
    if "strain_above_baseline" in report["insights"]:
        assert "hard_session_on_low_recovery" in report["insights"]
        assert report["summary"]["verdict"] == "harder_than_usual"

    cached = client.get("/v1/coach/day", params={"device": DEVICE, "day": DAY_KEY})
    assert cached.status_code == 200
    assert cached.json()["primary_workout_id"] == wid


@requires_docker
def test_no_workout_returns_no_workout_insight(client, clean_db):
    with psycopg.connect(clean_db) as conn:
        store.ensure_device(conn, DEVICE)
        conn.commit()
    r = client.post("/v1/coach/day", params={"device": DEVICE, "day": DAY_KEY})
    assert r.status_code == 200
    assert "no_workout_detected" in r.json()["insights"]


@requires_docker
def test_inferred_plan_flag_without_day_plan(client, clean_db):
    _seed_day_with_workout(clean_db)
    r = client.post("/v1/coach/day", params={"device": DEVICE, "day": DAY_KEY})
    report = r.json()
    assert report["inferred_plan"] is True
    assert "no_day_plan" in report["insights"]
    assert report["training_context"]["source"] == "inferred"


@requires_docker
def test_rest_day_without_workout(client, clean_db):
    with psycopg.connect(clean_db) as conn:
        store.ensure_device(conn, DEVICE)
        store.upsert_workout_day_plan(conn, DEVICE, {
            "day_key": DAY_KEY,
            "primary_workout_id": None,
            "activity_type": None,
            "crossfit_style": None,
            "blocks_done": [],
            "note": "Descanso",
            "prvn_reference_day_key": None,
            "is_rest_day": True,
            "saved_at": _epoch(DAY, 8, 0),
        })
        conn.commit()

    r = client.post("/v1/coach/day", params={"device": DEVICE, "day": DAY_KEY})
    assert r.status_code == 200, r.text
    report = r.json()
    assert report["summary"]["verdict"] == "rest_day"
    assert "rest_day_planned" in report["insights"]
    assert "no_workout_detected" not in report["insights"]
    assert report["training_context"]["is_rest_day"] is True
    assert report["training_context"]["user_note"] == "Descanso"


@requires_docker
def test_prvn_reference_day_insight(client, clean_db):
    ref_day = (DAY - _dt.timedelta(days=2)).isoformat()
    wid = _seed_day_with_workout(clean_db)
    with psycopg.connect(clean_db) as conn:
        store.upsert_workout_day_plan(conn, DEVICE, {
            "day_key": DAY_KEY,
            "primary_workout_id": wid,
            "activity_type": "crossfit",
            "crossfit_style": "qualifier",
            "blocks_done": ["metcon"],
            "note": None,
            "prvn_reference_day_key": ref_day,
            "is_rest_day": False,
            "saved_at": _epoch(DAY, 12, 0),
        })
        conn.commit()

    report = client.post("/v1/coach/day", params={"device": DEVICE, "day": DAY_KEY}).json()
    assert "prvn_reference_day" in report["insights"]
    assert report["training_context"]["prvn_reference_day_key"] == ref_day
    assert report["training_context"]["source"] == "prvn_reference"


@requires_docker
def test_activity_on_rest_day_insight(client, clean_db):
    wid = _seed_day_with_workout(clean_db)
    with psycopg.connect(clean_db) as conn:
        store.upsert_workout_day_plan(conn, DEVICE, {
            "day_key": DAY_KEY,
            "primary_workout_id": wid,
            "activity_type": "crossfit",
            "crossfit_style": None,
            "blocks_done": ["metcon"],
            "note": None,
            "prvn_reference_day_key": None,
            "is_rest_day": True,
            "saved_at": _epoch(DAY, 12, 0),
        })
        conn.commit()

    report = client.post("/v1/coach/day", params={"device": DEVICE, "day": DAY_KEY}).json()
    assert "activity_on_rest_day" in report["insights"]
    assert "rest_day_planned" not in report["insights"]
