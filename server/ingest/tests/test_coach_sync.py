"""Coach sync API — day plans + mobility completions (Task mobility #9)."""
import importlib

import psycopg
import pytest
from fastapi.testclient import TestClient

from app import read, store
from tests.conftest import requires_docker

DEVICE = "devCoach"
DAY = "2026-06-16"


@pytest.fixture
def client(clean_db, tmp_path, monkeypatch):
    monkeypatch.setenv("WHOOP_API_KEY", "secret")
    monkeypatch.setenv("WHOOP_DB_DSN", clean_db)
    monkeypatch.setenv("WHOOP_RAW_ROOT", str(tmp_path))
    import app.main as m
    importlib.reload(m)
    return TestClient(m.app, headers={"Authorization": "Bearer secret"})


def _day_plan_body(**overrides):
    body = {
        "device": DEVICE,
        "day": DAY,
        "primary_workout_id": "dev|1700000000",
        "activity_type": "crossfit",
        "crossfit_style": "qualifier",
        "blocks_done": ["metcon"],
        "note": "Open 26.2 scaled",
        "saved_at": 1700000000.0,
    }
    body.update(overrides)
    return body


@requires_docker
def test_put_and_get_day_plan(client, clean_db):
    r = client.put("/v1/day-plan", json=_day_plan_body(
        prvn_reference_day_key="2026-06-14",
        is_rest_day=False,
    ))
    assert r.status_code == 200, r.text
    row = r.json()
    assert row["activity_type"] == "crossfit"
    assert row["blocks_done"] == ["metcon"]
    assert row["prvn_reference_day_key"] == "2026-06-14"
    assert row["is_rest_day"] is False

    got = client.get(
        "/v1/day-plans",
        params={"device": DEVICE, "from": DAY, "to": DAY},
    ).json()
    assert len(got) == 1
    assert got[0]["primary_workout_id"] == "dev|1700000000"
    assert got[0]["prvn_reference_day_key"] == "2026-06-14"


@requires_docker
def test_put_day_plan_rest_and_prvn_reference(client, clean_db):
    r = client.put("/v1/day-plan", json=_day_plan_body(
        primary_workout_id=None,
        activity_type=None,
        crossfit_style=None,
        blocks_done=[],
        note="Descanso activo",
        prvn_reference_day_key=None,
        is_rest_day=True,
    ))
    assert r.status_code == 200, r.text
    row = r.json()
    assert row["is_rest_day"] is True
    assert row["note"] == "Descanso activo"


@requires_docker
def test_put_day_plan_rejects_invalid_prvn_reference(client):
    r = client.put("/v1/day-plan", json=_day_plan_body(prvn_reference_day_key="not-a-date"))
    assert r.status_code == 422


@requires_docker
def test_delete_day_plan(client, clean_db):
    client.put("/v1/day-plan", json=_day_plan_body())
    r = client.delete("/v1/day-plan", params={"device": DEVICE, "day": DAY})
    assert r.status_code == 200
    got = client.get(
        "/v1/day-plans",
        params={"device": DEVICE, "from": DAY, "to": DAY},
    ).json()
    assert got == []


@requires_docker
def test_put_day_plan_rejects_invalid_block(client):
    r = client.put("/v1/day-plan", json=_day_plan_body(blocks_done=["not_a_block"]))
    assert r.status_code == 422


@requires_docker
def test_post_and_get_mobility_completion(client, clean_db):
    body = {
        "device": DEVICE,
        "day_key": DAY,
        "session_kind": "preWorkout",
        "exercise_count": 8,
        "completed_at": 1700003600.0,
    }
    r = client.post("/v1/mobility-completion", json=body)
    assert r.status_code == 200, r.text
    assert r.json()["exercise_count"] == 8

    got = client.get(
        "/v1/mobility-completions",
        params={"device": DEVICE, "from": DAY, "to": DAY},
    ).json()
    assert len(got) == 1
    assert got[0]["session_kind"] == "preWorkout"


@requires_docker
def test_mobility_completion_upsert_updates_count(client, clean_db):
    body = {
        "device": DEVICE,
        "day_key": DAY,
        "session_kind": "daily",
        "exercise_count": 10,
        "completed_at": 1700000000.0,
    }
    client.post("/v1/mobility-completion", json=body)
    body["exercise_count"] = 12
    body["completed_at"] = 1700007200.0
    client.post("/v1/mobility-completion", json=body)

    with psycopg.connect(clean_db) as conn:
        rows = read.query_mobility_completions(conn, DEVICE, DAY, DAY)
    assert len(rows) == 1
    assert rows[0]["exercise_count"] == 12


@requires_docker
def test_mobility_completion_rejects_invalid_kind(client):
    r = client.post("/v1/mobility-completion", json={
        "device": DEVICE,
        "day_key": DAY,
        "session_kind": "invalid",
        "exercise_count": 5,
        "completed_at": 1700000000.0,
    })
    assert r.status_code == 422


@requires_docker
def test_coach_endpoints_require_auth(client):
    r = client.put("/v1/day-plan", json=_day_plan_body(), headers={"Authorization": ""})
    assert r.status_code == 401
