"""Unit tests for intraday stress scoring (no Docker required)."""
import datetime as _dt

from app.analysis.exercise import ExerciseSession
from app.analysis.stress import (
    QUALITY_GOOD,
    QUALITY_MOTION,
    QUALITY_SPARSE_RR,
    QUALITY_WORKOUT,
    WINDOW_S,
    baseline_from_samples,
    compute_windows,
)


def _epoch(day: _dt.date, h: int, m: int = 0) -> float:
    return _dt.datetime.combine(
        day, _dt.time(h, m), _dt.timezone.utc).timestamp()


def _still_rr_block(start: float, minutes: int, *, rr_ms: int) -> dict:
    n = minutes * 60
    hr, rr, grav = [], [], []
    for i in range(n):
        ts = start + i
        hr.append({"ts": ts, "bpm": 62})
        rr.append({"ts": ts, "rr_ms": rr_ms + (5 if i % 2 else -5)})
        grav.append({"ts": ts, "x": 0.0, "y": 0.0, "z": 1.0})
    return {"hr": hr, "rr": rr, "gravity": grav}


def _jitter_block(start: float, minutes: int) -> dict:
    n = minutes * 60
    hr, rr, grav = [], [], []
    for i in range(n):
        ts = start + i
        v = 1.0 if i % 2 == 0 else -1.0
        hr.append({"ts": ts, "bpm": 120})
        rr.append({"ts": ts, "rr_ms": 700})
        grav.append({"ts": ts, "x": v, "y": 0.0, "z": 0.0})
    return {"hr": hr, "rr": rr, "gravity": grav}


def test_baseline_requires_minimum_good_samples():
    samples = [{"quality": QUALITY_GOOD, "rmssd_ms": 40.0, "hr_bpm": 60}] * 5
    rmssd, hr = baseline_from_samples(samples)
    assert rmssd is None
    assert hr is None


def test_baseline_median_from_history():
    samples = [
        {"quality": QUALITY_GOOD, "rmssd_ms": 40.0, "hr_bpm": 60},
        {"quality": QUALITY_GOOD, "rmssd_ms": 50.0, "hr_bpm": 62},
    ] * 5
    rmssd, hr = baseline_from_samples(samples)
    assert rmssd == 45.0
    assert hr == 61


def test_low_hrv_raises_stress_score():
    day = _dt.date(2024, 1, 15)
    start = _epoch(day, 10)
    streams = _still_rr_block(start, int(WINDOW_S / 60) + 1, rr_ms=800)
    day_start, day_end = start, start + 86400
    windows = compute_windows(
        streams, [],
        day_start=day_start, day_end=day_start + WINDOW_S,
        baseline_rmssd=60.0, baseline_hr=58,
    )
    assert len(windows) == 1
    w = windows[0]
    assert w.quality == QUALITY_GOOD
    assert w.score is not None
    assert w.score > 1.2


def test_high_hrv_lowers_stress_score():
    day = _dt.date(2024, 1, 15)
    start = _epoch(day, 10)
    streams = _still_rr_block(start, int(WINDOW_S / 60) + 1, rr_ms=1050)
    windows = compute_windows(
        streams, [],
        day_start=start, day_end=start + WINDOW_S,
        baseline_rmssd=45.0, baseline_hr=62,
    )
    assert windows[0].score is not None
    assert windows[0].score < 1.2


def test_motion_window_not_scored():
    day = _dt.date(2024, 1, 15)
    start = _epoch(day, 10)
    streams = _jitter_block(start, int(WINDOW_S / 60) + 1)
    windows = compute_windows(
        streams, [],
        day_start=start, day_end=start + WINDOW_S,
        baseline_rmssd=50.0, baseline_hr=60,
    )
    assert windows[0].quality == QUALITY_MOTION
    assert windows[0].score is None


def test_workout_overlap_not_scored():
    day = _dt.date(2024, 1, 15)
    start = _epoch(day, 10)
    streams = _still_rr_block(start, int(WINDOW_S / 60) + 1, rr_ms=900)
    workout = ExerciseSession(
        start=start,
        end=start + WINDOW_S,
        avg_hr=140.0,
        peak_hr=160,
        strain=10.0,
        kind=None,
        duration_s=WINDOW_S,
    )
    windows = compute_windows(
        streams, [workout],
        day_start=start, day_end=start + WINDOW_S,
        baseline_rmssd=50.0, baseline_hr=60,
    )
    assert windows[0].quality == QUALITY_WORKOUT
    assert windows[0].score is None


def test_sparse_rr_not_scored():
    day = _dt.date(2024, 1, 15)
    start = _epoch(day, 10)
    streams = {"hr": [{"ts": start, "bpm": 70}], "rr": [], "gravity": [
        {"ts": start, "x": 0.0, "y": 0.0, "z": 1.0}
    ]}
    windows = compute_windows(
        streams, [],
        day_start=start, day_end=start + WINDOW_S,
        baseline_rmssd=50.0, baseline_hr=60,
    )
    assert windows[0].quality == QUALITY_SPARSE_RR
