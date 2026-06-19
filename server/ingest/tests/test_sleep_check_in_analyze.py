"""Tests for sleep check-in voice/text analysis."""
from app.analysis.sleep_check_in import (
    analyze_transcript,
    compute_alignment,
    detect_factors,
    infer_morning_feeling,
)


def test_detect_factors_spanish():
    text = "dormí mal por el calor y la ansiedad, cené tarde"
    factors = detect_factors(text)
    assert "heat" in factors
    assert "anxiety" in factors
    assert "lateDinner" in factors


def test_infer_feeling_bad():
    assert infer_morning_feeling("me levanté fatal, muy cansado") == 1


def test_analyze_with_strap_mismatch():
    result = analyze_transcript(
        "dormí regular, me costó dormir por ansiedad",
        recovery_pct=0.82,
    )
    assert result.morning_feeling in (2, 3)
    assert result.onset == "hard"
    assert "anxiety" in result.factors
    assert result.strap_recovery_pct == 82.0
    assert result.alignment == "strap_higher"
    assert "pulsera" in result.conclusion.lower()


def test_alignment_aligned():
    assert compute_alignment(80, 75) == "aligned"


def test_empty_transcript_raises():
    try:
        analyze_transcript("   ")
        assert False, "expected ValueError"
    except ValueError:
        pass
