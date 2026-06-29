"""Composite sleep score (0–100): strap objective metrics + optional check-in blend.

Objective score blends quantity (vs personal sleep need), efficiency, architecture
quality, and bedtime consistency. Recovery uses objective/100 only — never the
subjective-adjusted final score.
"""
from __future__ import annotations

import datetime as _dt
import json
import math
import statistics
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

# ── Sleep need ────────────────────────────────────────────────────────────────

DEFAULT_SLEEP_NEED_MIN: float = 480.0
MIN_NIGHTS_FOR_NEED: int = 5
NEED_HISTORY_NIGHTS: int = 14
NEED_CLAMP: tuple[float, float] = (360.0, 540.0)

# ── Objective component weights ───────────────────────────────────────────────

W_QUANTITY: float = 0.40
W_EFFICIENCY: float = 0.25
W_ARCHITECTURE: float = 0.25
W_CONSISTENCY: float = 0.10

# ── Subjective adjustments ────────────────────────────────────────────────────

ONSET_ADJ: dict[str, float] = {"easy": 5.0, "normal": 0.0, "hard": -10.0}

FACTOR_WEIGHTS: dict[str, float] = {
    "heat": -8.0,
    "cold": -6.0,
    "alcohol": -12.0,
    "anxiety": -10.0,
    "lateSport": -8.0,
    "lateDinner": -6.0,
    "stayedUpLate": -8.0,
    "noise": -7.0,
    "nightWakings": -10.0,
    "goodTemperature": 5.0,
    "quiet": 5.0,
    "fellAsleepFast": 4.0,
    "feelRecovered": 6.0,
}

SUBJ_BLEND_DEFAULT: float = 0.25
SUBJ_BLEND_MIN: float = 0.20
SUBJ_BLEND_MAX: float = 0.45
SUBJ_BLEND_MIN_HISTORY: int = 5
MISALIGN_THRESHOLD: float = 15.0


def _clamp(value: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, value))


def personal_sleep_need_min(recent_total_sleep_mins: Sequence[float]) -> float:
    """Median TST over recent nights; fallback 8 h until MIN_NIGHTS_FOR_NEED."""
    vals = [float(v) for v in recent_total_sleep_mins if v is not None and v > 0]
    if len(vals) < MIN_NIGHTS_FOR_NEED:
        return DEFAULT_SLEEP_NEED_MIN
    med = statistics.median(vals)
    return max(NEED_CLAMP[0], min(NEED_CLAMP[1], med))


def regularity_score(bedtime_minutes: Sequence[float]) -> float | None:
    """0–100 bedtime consistency (matches iOS SleepQualityBuilder)."""
    if len(bedtime_minutes) < 3:
        return None
    mean = statistics.fmean(bedtime_minutes)
    variance = sum((m - mean) ** 2 for m in bedtime_minutes) / len(bedtime_minutes)
    std_dev = math.sqrt(variance)
    return _clamp(100.0 - std_dev * 1.1)


def _stage_pcts(deep_min: float, rem_min: float, light_min: float) -> tuple[float, float]:
    tst = deep_min + rem_min + light_min
    if tst <= 0:
        return 0.0, 0.0
    return deep_min / tst * 100.0, rem_min / tst * 100.0


def architecture_score(
    *,
    disturbances: int,
    sleep_latency_min: float,
    deep_min: float,
    rem_min: float,
    light_min: float,
    deep_baseline_pct: float | None = None,
    rem_baseline_pct: float | None = None,
) -> float:
    """100-based architecture proxy with penalties for fragmentation/latency."""
    score = 100.0
    dist = max(0, int(disturbances or 0))
    score -= min(25.0, dist * 5.0)

    lat = max(0.0, float(sleep_latency_min or 0.0))
    if lat > 20.0:
        score -= min(20.0, (lat - 20.0))

    deep_pct, rem_pct = _stage_pcts(deep_min, rem_min, light_min)
    if deep_baseline_pct is not None and deep_pct > 0:
        z = abs(deep_pct - deep_baseline_pct) / max(5.0, deep_baseline_pct * 0.15)
        if z > 1.5:
            score -= min(10.0, (z - 1.5) * 5.0)
    if rem_baseline_pct is not None and rem_pct > 0:
        z = abs(rem_pct - rem_baseline_pct) / max(5.0, rem_baseline_pct * 0.15)
        if z > 1.5:
            score -= min(10.0, (z - 1.5) * 5.0)

    return _clamp(score)


def quantity_score(total_sleep_min: float, sleep_need_min: float) -> float:
    if sleep_need_min <= 0:
        return 0.0
    return _clamp(min(100.0, total_sleep_min / sleep_need_min * 100.0))


def efficiency_score(efficiency: float | None) -> float:
    if efficiency is None:
        return 0.0
    eff = efficiency * 100.0 if efficiency <= 1.0 else efficiency
    return _clamp(eff)


def objective_sleep_score(
    *,
    total_sleep_min: float,
    efficiency: float | None,
    disturbances: int,
    sleep_latency_min: float,
    deep_min: float,
    rem_min: float,
    light_min: float,
    sleep_need_min: float,
    consistency_score: float | None,
    deep_baseline_pct: float | None = None,
    rem_baseline_pct: float | None = None,
) -> tuple[float, dict[str, float]]:
    """Weighted objective composite and per-component breakdown (0–100)."""
    components = {
        "quantity": quantity_score(total_sleep_min, sleep_need_min),
        "efficiency": efficiency_score(efficiency),
        "architecture": architecture_score(
            disturbances=disturbances,
            sleep_latency_min=sleep_latency_min,
            deep_min=deep_min,
            rem_min=rem_min,
            light_min=light_min,
            deep_baseline_pct=deep_baseline_pct,
            rem_baseline_pct=rem_baseline_pct,
        ),
        "consistency": consistency_score if consistency_score is not None else 70.0,
    }
    weights = {
        "quantity": W_QUANTITY,
        "efficiency": W_EFFICIENCY,
        "architecture": W_ARCHITECTURE,
        "consistency": W_CONSISTENCY if consistency_score is not None else 0.0,
    }
    w_sum = sum(weights.values())
    if w_sum <= 0:
        w_sum = W_QUANTITY + W_EFFICIENCY + W_ARCHITECTURE
        weights = {"quantity": W_QUANTITY, "efficiency": W_EFFICIENCY, "architecture": W_ARCHITECTURE}
        w_sum = sum(weights.values())
    objective = sum(components[k] * weights[k] for k in weights) / w_sum
    components["sleep_need_min"] = sleep_need_min
    return _clamp(objective), components


def subjective_score_from_check_in(check_in: Mapping[str, Any]) -> float:
    feeling = int(check_in.get("morning_feeling") or 3)
    base = float(feeling * 20)
    onset = str(check_in.get("onset") or "normal").lower()
    base += ONSET_ADJ.get(onset, 0.0)
    factors = check_in.get("factors") or []
    if isinstance(factors, str):
        try:
            factors = json.loads(factors)
        except json.JSONDecodeError:
            factors = []
    for f in factors:
        base += FACTOR_WEIGHTS.get(str(f), 0.0)
    return _clamp(base)


def subjective_blend_weight(
    history: Sequence[tuple[float, float]],
) -> float:
    """Adaptive subjective weight from past |feeling − objective| pairs."""
    if len(history) < SUBJ_BLEND_MIN_HISTORY:
        return SUBJ_BLEND_DEFAULT
    errors = [abs(f - o) for f, o in history]
    mean_err = statistics.fmean(errors)
    if mean_err > MISALIGN_THRESHOLD:
        t = min(1.0, (mean_err - MISALIGN_THRESHOLD) / 20.0)
        return SUBJ_BLEND_DEFAULT + t * (SUBJ_BLEND_MAX - SUBJ_BLEND_DEFAULT)
    if mean_err < 8.0:
        return SUBJ_BLEND_MIN
    return SUBJ_BLEND_DEFAULT


def compute_alignment(subjective: float, objective: float) -> str:
    delta = subjective - objective
    if abs(delta) <= MISALIGN_THRESHOLD:
        return "aligned"
    if delta < -MISALIGN_THRESHOLD:
        return "strap_higher"
    return "body_higher"


def blend_sleep_score(
    objective: float,
    subjective: float | None,
    *,
    history: Sequence[tuple[float, float]] | None = None,
) -> tuple[float, float, str | None]:
    """Return (final_score, subjective_weight, alignment)."""
    if subjective is None:
        return objective, 0.0, None
    w = subjective_blend_weight(history or [])
    final = _clamp((1.0 - w) * objective + w * subjective)
    return final, w, compute_alignment(subjective, objective)


@dataclass(frozen=True)
class SleepScoreResult:
    sleep_score: float
    sleep_score_objective: float
    breakdown: dict[str, Any]

    def as_metrics(self) -> dict[str, Any]:
        return {
            "sleep_score": self.sleep_score,
            "sleep_score_objective": self.sleep_score_objective,
            "sleep_score_breakdown": self.breakdown,
        }


def compute_sleep_score(
    *,
    total_sleep_min: float,
    efficiency: float | None,
    disturbances: int,
    sleep_latency_min: float,
    deep_min: float,
    rem_min: float,
    light_min: float,
    recent_total_sleep_mins: Sequence[float],
    bedtime_minutes: Sequence[float],
    deep_baseline_pct: float | None = None,
    rem_baseline_pct: float | None = None,
    check_in: Mapping[str, Any] | None = None,
    blend_history: Sequence[tuple[float, float]] | None = None,
) -> SleepScoreResult:
    need = personal_sleep_need_min(recent_total_sleep_mins)
    consistency = regularity_score(bedtime_minutes)
    objective, components = objective_sleep_score(
        total_sleep_min=total_sleep_min,
        efficiency=efficiency,
        disturbances=disturbances,
        sleep_latency_min=sleep_latency_min,
        deep_min=deep_min,
        rem_min=rem_min,
        light_min=light_min,
        sleep_need_min=need,
        consistency_score=consistency,
        deep_baseline_pct=deep_baseline_pct,
        rem_baseline_pct=rem_baseline_pct,
    )
    subjective = subjective_score_from_check_in(check_in) if check_in else None
    final, w_subj, alignment = blend_sleep_score(
        objective, subjective, history=blend_history)

    breakdown: dict[str, Any] = {
        "objective": round(objective, 1),
        "subjective": round(subjective, 1) if subjective is not None else None,
        "final": round(final, 1),
        "weights": {
            "quantity": W_QUANTITY,
            "efficiency": W_EFFICIENCY,
            "architecture": W_ARCHITECTURE,
            "consistency": W_CONSISTENCY if consistency is not None else 0.0,
        },
        "components": {k: round(v, 1) for k, v in components.items() if k != "sleep_need_min"},
        "sleep_need_min": round(need, 1),
        "subjective_blend": round(w_subj, 2),
        "alignment": alignment,
        "provisional": len(recent_total_sleep_mins) < MIN_NIGHTS_FOR_NEED,
    }
    return SleepScoreResult(
        sleep_score=final,
        sleep_score_objective=objective,
        breakdown=breakdown,
    )


def bedtime_minute_from_sleep_start(sleep_start: Any) -> float | None:
    """Extract minutes-since-midnight from sleep_start (epoch or datetime)."""
    if sleep_start is None:
        return None
    if isinstance(sleep_start, (int, float)):
        dt = _dt.datetime.fromtimestamp(float(sleep_start), _dt.timezone.utc)
    elif isinstance(sleep_start, _dt.datetime):
        dt = sleep_start if sleep_start.tzinfo else sleep_start.replace(tzinfo=_dt.timezone.utc)
    else:
        return None
    return float(dt.hour * 60 + dt.minute)


def stage_baselines_from_history(
    rows: Sequence[Mapping[str, Any]],
) -> tuple[float | None, float | None]:
    """Trailing deep% / rem% medians from daily_metrics rows."""
    deep_pcts: list[float] = []
    rem_pcts: list[float] = []
    for r in rows:
        deep = float(r.get("deep_min") or 0)
        rem = float(r.get("rem_min") or 0)
        light = float(r.get("light_min") or 0)
        dp, rp = _stage_pcts(deep, rem, light)
        if dp > 0 or rp > 0:
            deep_pcts.append(dp)
            rem_pcts.append(rp)
    if len(deep_pcts) < 3:
        return None, None
    return statistics.median(deep_pcts), statistics.median(rem_pcts)
