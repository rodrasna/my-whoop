"""Training coach LLM explain (task-09 Phase B)."""
import importlib

import pytest
from fastapi.testclient import TestClient

from app.analysis import training_coach_explain
from tests.conftest import requires_docker

DEVICE = "devCoachX"
DAY = "2026-06-16"


@pytest.fixture
def client(clean_db, tmp_path, monkeypatch):
    monkeypatch.setenv("WHOOP_API_KEY", "secret")
    monkeypatch.setenv("WHOOP_DB_DSN", clean_db)
    monkeypatch.setenv("WHOOP_RAW_ROOT", str(tmp_path))
    import app.main as m
    importlib.reload(m)
    return TestClient(m.app, headers={"Authorization": "Bearer secret"})


def _sample_report():
    return {
        "day": DAY,
        "style": "qualifier",
        "activity_type": "crossfit",
        "primary_workout_id": "dev|1",
        "summary": {
            "strain_vs_baseline_pct": 18.0,
            "verdict": "harder_than_usual",
            "recovery_pct": 40.0,
        },
        "blocks": [{"kind": "metcon", "label": "WOD"}],
        "insights": ["strain_above_baseline", "hard_session_on_low_recovery"],
        "data_quality": "good",
        "inferred_plan": False,
    }


@requires_docker
def test_explain_returns_template_without_openai(client, clean_db, monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    compute = client.post("/v1/coach/day", params={"device": DEVICE, "day": DAY})
    assert compute.status_code == 200

    r = client.post("/v1/coach/explain", json={
        "device": DEVICE,
        "day": DAY,
        "include_note": False,
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["source"] == "template"
    assert len(body["narrative"]) > 20

    cached = client.post("/v1/coach/explain", json={"device": DEVICE, "day": DAY})
    assert cached.status_code == 200
    assert cached.json()["source"] == "cached"


@requires_docker
def test_explain_requires_report(client):
    r = client.post("/v1/coach/explain", json={"device": DEVICE, "day": DAY})
    assert r.status_code == 404


def test_deterministic_narrative_mentions_verdict():
    text = training_coach_explain.deterministic_narrative(_sample_report())
    assert "duro" in text.lower() or "habitual" in text.lower()


def test_explain_with_mock_llm(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")

    def _fake_llm(report, *, note=None):
        return "Sesión dura con strain por encima de tu media."

    monkeypatch.setattr(training_coach_explain, "explain_with_llm", _fake_llm)
    narrative, source = training_coach_explain.explain_report(_sample_report())
    assert source == "llm"
    assert "strain" in narrative.lower()
