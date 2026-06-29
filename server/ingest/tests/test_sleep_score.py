"""Tests for composite sleep score."""
import pytest

from app.analysis.sleep_score import (
    architecture_score,
    blend_sleep_score,
    compute_sleep_score,
    personal_sleep_need_min,
    subjective_blend_weight,
    subjective_score_from_check_in,
)


def test_personal_sleep_need_fallback():
    assert personal_sleep_need_min([]) == 480.0
    assert personal_sleep_need_min([400, 420]) == 480.0


def test_personal_sleep_need_median():
    mins = [420.0] * 6
    assert personal_sleep_need_min(mins) == 420.0


def test_high_efficiency_low_subjective_factors():
    """Efficiency can be high but alcohol/heat drag subjective score down."""
    check_in = {
        "morning_feeling": 2,
        "onset": "hard",
        "factors": ["alcohol", "heat"],
    }
    subj = subjective_score_from_check_in(check_in)
    assert subj < 50

    result = compute_sleep_score(
        total_sleep_min=480,
        efficiency=0.92,
        disturbances=1,
        sleep_latency_min=15,
        deep_min=90,
        rem_min=100,
        light_min=290,
        recent_total_sleep_mins=[450, 460, 470, 480, 490],
        bedtime_minutes=[1380, 1390, 1375],
        check_in=check_in,
    )
    assert result.sleep_score_objective > 75
    assert result.sleep_score < result.sleep_score_objective


def test_no_check_in_equals_objective():
    result = compute_sleep_score(
        total_sleep_min=420,
        efficiency=0.85,
        disturbances=2,
        sleep_latency_min=25,
        deep_min=80,
        rem_min=90,
        light_min=250,
        recent_total_sleep_mins=[400, 410, 420, 430, 440],
        bedtime_minutes=[1380, 1390, 1375],
        check_in=None,
    )
    assert result.sleep_score == pytest.approx(result.sleep_score_objective)


def test_subjective_blend_weight_increases_with_misalignment():
    aligned = [(70, 72), (80, 78), (60, 62), (75, 73), (65, 67)]
    misaligned = [(40, 85), (35, 90), (45, 88), (50, 82), (38, 86)]
    assert subjective_blend_weight(misaligned) > subjective_blend_weight(aligned)


def test_architecture_penalizes_disturbances():
    low = architecture_score(
        disturbances=0, sleep_latency_min=10,
        deep_min=90, rem_min=100, light_min=290,
    )
    high = architecture_score(
        disturbances=6, sleep_latency_min=45,
        deep_min=90, rem_min=100, light_min=290,
    )
    assert low > high


def test_blend_sleep_score_without_subjective():
    final, w, align = blend_sleep_score(82.0, None)
    assert final == 82.0
    assert w == 0.0
    assert align is None
