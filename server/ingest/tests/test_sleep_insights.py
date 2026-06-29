"""Tests for sleep insights engine."""
from app.analysis.sleep_insights import build_sleep_insights, factor_impacts


def _ci(day, feeling, factors=None):
    return {
        "day_key": day,
        "morning_feeling": feeling,
        "onset": "normal",
        "factors": factors or [],
    }


def _daily(day, efficiency=0.85, disturbances=1, deep_min=80):
    return {
        "day": day,
        "efficiency": efficiency,
        "disturbances": disturbances,
        "deep_min": deep_min,
        "rem_min": 90,
        "light_min": 250,
        "sleep_score_objective": efficiency * 100,
    }


def test_not_ready_with_few_check_ins():
    out = build_sleep_insights([_ci("2026-06-01", 3)], [])
    assert out["ready"] is False
    assert out["check_in_count"] == 1


def test_alcohol_impact():
    check_ins = []
    daily = []
    for i in range(8):
        day = f"2026-06-{i+1:02d}"
        factors = ["alcohol"] if i % 2 == 0 else []
        feeling = 2 if "alcohol" in factors else 4
        check_ins.append(_ci(day, feeling, factors))
        daily.append(_daily(day, efficiency=0.88 if feeling >= 4 else 0.86))

    impacts = factor_impacts(check_ins)
    alcohol = next(x for x in impacts if x["factor_id"] == "alcohol")
    assert alcohol["delta_feeling"] < -10

    out = build_sleep_insights(check_ins, daily)
    assert out["ready"] is True
    assert out["top_insight"] is not None
    assert "Alcohol" in out["top_insight"]
