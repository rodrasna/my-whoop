"""
stress.py — Intraday physiological stress from HR + RR (RMSSD) + motion gate.

WHOOP-like 0–3 score: compares short-window RMSSD and HR to a personal baseline
built from recent rest windows. Exercise overlap and sustained motion suppress
scoring (quality flags) so workouts are not misread as mental stress.

All outputs are APPROXIMATE wellness proxies, not medical advice.
"""
from __future__ import annotations

import datetime as _dt
import math
import statistics
from dataclasses import dataclass
from typing import Any, Sequence

from . import activity as _activity
from . import exercise as _exercise
from . import hrv as _hrv
from .exercise import ExerciseSession, MOTION_THRESHOLD

# Windowing
WINDOW_S: float = 300.0
STEP_S: float = 300.0

# Baseline pool: rest windows with quality=good from prior days
BASELINE_LOOKBACK_DAYS: int = 14
MIN_BASELINE_SAMPLES: int = 8

# Motion: fraction of samples above MOTION_THRESHOLD allowed for a "rest" window
MAX_ACTIVE_MOTION_FRAC: float = 0.15

# Workout overlap (same idea as hr_elevation skip)
WORKOUT_OVERLAP_FRAC: float = 0.35

# Score mapping weights (tunable after field calibration)
HRV_STRESS_WEIGHT: float = 0.6
HR_STRESS_WEIGHT: float = 0.4
SCORE_CENTER: float = 1.0
SCORE_SCALE: float = 0.8
SCORE_MIN: float = 0.0
SCORE_MAX: float = 3.0

QUALITY_GOOD = "good"
QUALITY_SPARSE_RR = "sparse_rr"
QUALITY_MOTION = "motion"
QUALITY_WORKOUT = "workout"


@dataclass(frozen=True)
class StressSample:
    ts: float
    score: float | None
    rmssd_ms: float | None
    hr_bpm: int | None
    motion_var: float | None
    quality: str


def _day_bounds_utc(day: _dt.date) -> tuple[float, float]:
    start = _dt.datetime.combine(day, _dt.time(0, 0), _dt.timezone.utc)
    end = start + _dt.timedelta(days=1)
    return start.timestamp(), end.timestamp()


def _window_rmssd(rr_rows: Sequence[dict], lo: float, hi: float) -> float | None:
    """RMSSD (ms) for RR intervals with ts in [lo, hi], or None if too sparse."""
    rr_ms = [int(r["rr_ms"]) for r in rr_rows if lo <= float(r["ts"]) < hi]
    if len(rr_ms) < _hrv.MIN_BEATS:
        return None
    nn, _, _, _ = _hrv.clean_rr(rr_ms)
    if nn.size < 2:
        return None
    val = _hrv.rmssd_ms(nn)
    return val if math.isfinite(val) and val > 0 else None


def _window_mean_hr(hr_rows: Sequence[dict], lo: float, hi: float) -> int | None:
    bpms = [int(r["bpm"]) for r in hr_rows if lo <= float(r["ts"]) < hi]
    if not bpms:
        return None
    return int(round(statistics.fmean(bpms)))


def _motion_active_fraction(motion: Sequence[dict], lo: float, hi: float) -> float:
    pts = [p for p in motion if lo <= float(p["ts"]) < hi]
    if not pts:
        return 0.0
    active = sum(
        1 for p in pts
        if math.isfinite(p["intensity"]) and p["intensity"] > MOTION_THRESHOLD
    )
    return active / len(pts)


def _window_motion_var(motion: Sequence[dict], lo: float, hi: float) -> float | None:
    vals = [
        p["intensity"] for p in motion
        if lo <= float(p["ts"]) < hi and math.isfinite(p["intensity"])
    ]
    if len(vals) < 2:
        return None
    return round(statistics.pvariance(vals), 5)


def _overlaps_workout(lo: float, hi: float, workouts: Sequence[ExerciseSession]) -> bool:
    return _exercise._overlaps_existing(lo, hi, workouts, WORKOUT_OVERLAP_FRAC)


def _activation_score(
    rmssd_ms: float,
    hr_bpm: int,
    baseline_rmssd: float,
    baseline_hr: float,
) -> float:
    hrv_denom = max(baseline_rmssd * 0.15, 5.0)
    hr_denom = max(baseline_hr * 0.10, 3.0)
    z_hrv = (baseline_rmssd - rmssd_ms) / hrv_denom
    z_hr = (hr_bpm - baseline_hr) / hr_denom
    activation = HRV_STRESS_WEIGHT * z_hrv + HR_STRESS_WEIGHT * z_hr
    raw = activation * SCORE_SCALE + SCORE_CENTER
    return max(SCORE_MIN, min(SCORE_MAX, raw))


def compute_windows(
    streams: dict[str, list[dict]],
    workouts: Sequence[ExerciseSession],
    *,
    day_start: float,
    day_end: float,
    baseline_rmssd: float | None,
    baseline_hr: float | None,
) -> list[StressSample]:
    """Build 5-minute stress windows for a calendar day."""
    hr_rows = streams.get("hr") or []
    rr_rows = streams.get("rr") or []
    motion = _activity.activity_series(streams.get("gravity") or [])

    has_baseline = (
        baseline_rmssd is not None
        and baseline_hr is not None
        and baseline_rmssd > 0
    )
    can_score = has_baseline

    out: list[StressSample] = []
    t = day_start
    while t + WINDOW_S <= day_end:
        lo, hi = t, t + WINDOW_S
        quality = QUALITY_GOOD
        score: float | None = None

        if _overlaps_workout(lo, hi, workouts):
            quality = QUALITY_WORKOUT
        elif _motion_active_fraction(motion, lo, hi) > MAX_ACTIVE_MOTION_FRAC:
            quality = QUALITY_MOTION

        rmssd = _window_rmssd(rr_rows, lo, hi)
        hr = _window_mean_hr(hr_rows, lo, hi)
        mvar = _window_motion_var(motion, lo, hi)

        if quality == QUALITY_GOOD:
            if rmssd is None or hr is None:
                quality = QUALITY_SPARSE_RR
            elif can_score:
                score = _activation_score(rmssd, hr, baseline_rmssd, baseline_hr)

        out.append(StressSample(
            ts=lo,
            score=round(score, 2) if score is not None else None,
            rmssd_ms=round(rmssd, 2) if rmssd is not None else None,
            hr_bpm=hr,
            motion_var=mvar,
            quality=quality,
        ))
        t += STEP_S
    return out


def baseline_from_samples(samples: Sequence[dict]) -> tuple[float | None, float | None]:
    """Median RMSSD and HR from prior ``good`` stress rows (dicts from DB)."""
    good = [s for s in samples if s.get("quality") == QUALITY_GOOD and s.get("rmssd_ms") is not None]
    if len(good) < MIN_BASELINE_SAMPLES:
        return None, None
    rmssd_vals = [float(s["rmssd_ms"]) for s in good]
    hr_vals = [int(s["hr_bpm"]) for s in good if s.get("hr_bpm") is not None]
    if len(hr_vals) < MIN_BASELINE_SAMPLES:
        return statistics.median(rmssd_vals), None
    return statistics.median(rmssd_vals), int(round(statistics.median(hr_vals)))


def samples_to_dicts(device_id: str, rows: Sequence[StressSample]) -> list[dict[str, Any]]:
    return [
        {
            "device_id": device_id,
            "ts": s.ts,
            "score": s.score,
            "rmssd_ms": s.rmssd_ms,
            "hr_bpm": s.hr_bpm,
            "motion_var": s.motion_var,
            "quality": s.quality,
        }
        for s in rows
    ]


def summarize_day(samples: Sequence[StressSample]) -> dict[str, Any]:
    scored = [s.score for s in samples if s.score is not None]
    return {
        "window_count": len(samples),
        "scored_count": len(scored),
        "stress_avg": round(statistics.fmean(scored), 2) if scored else None,
        "stress_peak": round(max(scored), 2) if scored else None,
        "calibrating": len(scored) == 0,
    }


def compute_stress_day(
    conn,
    device_id: str,
    day: _dt.date,
    day_streams: dict[str, list[dict]],
    workouts: Sequence[ExerciseSession],
) -> dict[str, Any]:
    """Delete + recompute stress windows for ``day``; return summary dict."""
    from .. import read, store

    day_start, day_end = _day_bounds_utc(day)
    prior_start = day - _dt.timedelta(days=BASELINE_LOOKBACK_DAYS)
    prior_end = day - _dt.timedelta(days=1)
    prior = read.query_stress_samples(conn, device_id, prior_start, prior_end)
    baseline_rmssd, baseline_hr = baseline_from_samples(prior)
    windows = compute_windows(
        day_streams,
        workouts,
        day_start=day_start,
        day_end=day_end,
        baseline_rmssd=baseline_rmssd,
        baseline_hr=baseline_hr,
    )
    store.delete_stress_for_day(conn, device_id, day)
    store.upsert_stress_samples(conn, device_id, samples_to_dicts(device_id, windows))
    summary = summarize_day(windows)
    summary["baseline_rmssd"] = baseline_rmssd
    summary["baseline_hr"] = baseline_hr
    return summary
