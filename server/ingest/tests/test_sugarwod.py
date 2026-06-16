"""Tests for SugarWOD → PRVN text mapping."""
from __future__ import annotations

from app.sugarwod.sync import _classify_title, _render_day, fetch_prvn_week_text


class _FakeClient:
    track_name = "PRVN ESPAÑOL"
    track_key = "PRVN ESPAÑOL"

    def __init__(self, workouts):
        self._workouts = workouts

    def fetch_workouts_week(self, week: str):
        return self._workouts


def test_classify_prvn_titles():
    assert _classify_title("Warmup") == "CALENTAMIENTO"
    assert _classify_title("Fuerza") == "FUERZA"
    assert _classify_title('"Viper"') == "WOD"
    assert _classify_title("Accesorios") == "ACCESORIOS"
    assert _classify_title("Monostructural") is None
    assert _classify_title("PRVN Recuperacion") is None
    assert _classify_title("Opcion 1) BIke") is None
    assert _classify_title("Weightlifting") == "FUERZA"
    assert _classify_title("Skills") == "FUERZA"
    assert _classify_title("Haltero") == "FUERZA"


def test_render_day_groups_sections():
    workouts = [
        {"title": "Warmup", "description": "Bike easy", "whiteboardDisplayOrder": 1},
        {"title": "Fuerza", "description": "Back Squat 5x5", "whiteboardDisplayOrder": 2},
        {"title": '"Viper"', "description": "For time 3 rounds", "whiteboardDisplayOrder": 3},
        {"title": "Accesorios", "description": "3x12 GHD", "whiteboardDisplayOrder": 4},
    ]
    text = _render_day(workouts)
    assert "FUERZA" in text
    assert "WOD" in text
    assert "ACCESORIOS" in text
    assert "MONOSTRUCTURAL" not in text.upper()
    assert text.index("FUERZA") < text.index("WOD") < text.index("ACCESORIOS")


def test_fetch_prvn_week_text_monday():
    workouts = [
        {
            "title": "Fuerza",
            "description": "Squat 5x5",
            "scheduledDateInteger": 20260616,
            "whiteboardDisplayOrder": 1,
        },
        {
            "title": '"Taipan"',
            "description": "AMRAP 11",
            "scheduledDateInteger": 20260616,
            "whiteboardDisplayOrder": 2,
        },
    ]
    text = fetch_prvn_week_text("20260615", _FakeClient(workouts))
    assert "MARTES" in text
    assert "FUERZA" in text
    assert "WOD" in text
    assert "Squat 5x5" in text
