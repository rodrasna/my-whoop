"""Deterministic training-day coach — compare today's bout vs personal baseline.

Phase A (task-09): rule-based insights only; no LLM. Inputs: workout_day_plans,
exercise_sessions, daily_metrics. Output: JSON-serializable ``TrainingDayReport``.
"""
from __future__ import annotations

import datetime as _dt
import statistics
from typing import Any

from .. import read

BASELINE_DAYS = 30
STRAIN_DELTA_PCT = 10.0
HR_DELTA_PCT = 8.0
Z4_DELTA_PCT = 15.0
LOW_RECOVERY_PCT = 45.0
MIN_BASELINE_SESSIONS = 2

_BLOCK_LABELS = {
    "warmup": "Calentamiento",
    "strength": "Fuerza",
    "metcon": "WOD",
    "accessory": "Accesorios",
    "other": "Otro",
}


def _parse_day(day_key: str) -> _dt.date:
    return _dt.date.fromisoformat(day_key)


def _ts_epoch(ts) -> int:
    if isinstance(ts, (int, float)):
        return int(ts)
    if hasattr(ts, "timestamp"):
        return int(ts.timestamp())
    raise TypeError(f"unexpected timestamp type: {type(ts)!r}")


def _workout_row_id(row: dict) -> str:
    return f"{row['device_id']}|{_ts_epoch(row['start_ts'])}"


def _day_key_from_row(row: dict) -> str:
    ts = row["start_ts"]
    if hasattr(ts, "date"):
        d = ts.date() if ts.tzinfo is None else ts.astimezone(_dt.timezone.utc).date()
    else:
        d = _dt.datetime.fromtimestamp(_ts_epoch(ts), _dt.timezone.utc).date()
    return d.isoformat()


def _zone_pct(zone_time_pct: dict | None, zones: tuple[int, ...]) -> float:
    if not zone_time_pct:
        return 0.0
    total = 0.0
    for z in zones:
        total += float(zone_time_pct.get(str(z), zone_time_pct.get(z, 0.0)) or 0.0)
    return total


def _mean(vals: list[float]) -> float | None:
    return statistics.mean(vals) if vals else None


def _pct_delta(current: float | None, baseline: float | None) -> float | None:
    if current is None or baseline is None or baseline == 0:
        return None
    return round((current - baseline) / baseline * 100.0, 1)


def _session_metrics(row: dict) -> dict[str, Any]:
    zt = row.get("zone_time_pct") or {}
    return {
        "duration_s": row.get("duration_s"),
        "avg_hr": row.get("avg_hr"),
        "peak_hr": row.get("peak_hr"),
        "strain": row.get("strain"),
        "z2plus_pct": round(_zone_pct(zt, (2, 3, 4, 5)), 1),
        "z4plus_pct": round(_zone_pct(zt, (4, 5)), 1),
    }


def _match_baseline(
    row: dict,
    plan_by_day: dict[str, dict],
    *,
    activity_type: str | None,
    crossfit_style: str | None,
) -> bool:
    day_key = _day_key_from_row(row)
    pl = plan_by_day.get(day_key)
    if activity_type:
        if not pl or pl.get("activity_type") != activity_type:
            return False
    if crossfit_style:
        if not pl or pl.get("crossfit_style") != crossfit_style:
            return False
    return True


def _training_context(plan: dict | None, day_key: str) -> dict[str, Any]:
    """User-declared training context from workout_day_plans (PRVN ref, rest, note)."""
    if not plan:
        return {
            "is_rest_day": False,
            "prvn_reference_day_key": None,
            "user_note": None,
            "source": "inferred",
        }
    ref = plan.get("prvn_reference_day_key")
    is_rest = bool(plan.get("is_rest_day"))
    note = (plan.get("note") or "").strip() or None
    if is_rest:
        source = "rest"
    elif ref and ref != day_key:
        source = "prvn_reference"
    elif (
        plan.get("blocks_done")
        or plan.get("activity_type")
        or plan.get("primary_workout_id")
        or note
    ):
        source = "user_plan"
    else:
        source = "calendar"
    return {
        "is_rest_day": is_rest,
        "prvn_reference_day_key": ref if ref and ref != day_key else None,
        "user_note": note,
        "source": source,
    }


def _plan_insights(ctx: dict[str, Any], *, has_workout: bool) -> list[str]:
    out: list[str] = []
    if ctx.get("is_rest_day"):
        out.append("activity_on_rest_day" if has_workout else "rest_day_planned")
    elif not has_workout:
        out.append("no_workout_detected")
    if ctx.get("prvn_reference_day_key"):
        out.append("prvn_reference_day")
    return out


def _attach_training_context(report: dict[str, Any], ctx: dict[str, Any]) -> dict[str, Any]:
    report["training_context"] = ctx
    return report


def compute_day_report(conn, device_id: str, day_key: str) -> dict[str, Any]:
    """Build a training-day report for ``day_key`` (YYYY-MM-DD)."""
    day = _parse_day(day_key)
    plans = read.query_workout_day_plans(conn, device_id, day, day)
    plan = plans[0] if plans else None
    ctx = _training_context(plan, day_key)

    workouts = read.query_workouts(conn, device_id, day, day)
    primary: dict | None = None
    if plan and plan.get("primary_workout_id"):
        pid = plan["primary_workout_id"]
        for w in workouts:
            if _workout_row_id(w) == pid:
                primary = w
                break
    if primary is None and workouts:
        primary = max(workouts, key=lambda w: float(w.get("strain") or 0.0))

    daily_rows = read.query_daily(conn, device_id, day, day)
    recovery = daily_rows[0].get("recovery") if daily_rows else None

    if primary is None:
        insights = _plan_insights(ctx, has_workout=False)
        verdict = "rest_day" if ctx["is_rest_day"] else "no_workout"
        return _attach_training_context({
            "day": day_key,
            "style": plan.get("crossfit_style") if plan else None,
            "activity_type": plan.get("activity_type") if plan else None,
            "primary_workout_id": None,
            "summary": {"verdict": verdict, "recovery_pct": recovery},
            "blocks": [],
            "insights": insights,
            "data_quality": "rest_day" if ctx["is_rest_day"] else "no_workout",
            "inferred_plan": plan is None,
        }, ctx)

    activity_type = plan.get("activity_type") if plan else None
    crossfit_style = plan.get("crossfit_style") if plan else None

    start_baseline = day - _dt.timedelta(days=BASELINE_DAYS)
    hist_workouts = read.query_workouts(
        conn, device_id, start_baseline, day - _dt.timedelta(days=1))
    hist_plans = read.query_workout_day_plans(
        conn, device_id, start_baseline, day - _dt.timedelta(days=1))
    plan_by_day = {p["day_key"]: p for p in hist_plans}

    baseline = [
        w for w in hist_workouts
        if _match_baseline(
            w, plan_by_day,
            activity_type=activity_type,
            crossfit_style=crossfit_style,
        )
    ]

    p_metrics = _session_metrics(primary)
    b_strains = [float(w["strain"]) for w in baseline if w.get("strain") is not None]
    b_hrs = [float(w["avg_hr"]) for w in baseline if w.get("avg_hr") is not None]
    b_z4 = [_zone_pct(w.get("zone_time_pct"), (4, 5)) for w in baseline]

    strain_delta = _pct_delta(
        float(primary["strain"]) if primary.get("strain") is not None else None,
        _mean(b_strains),
    )
    hr_delta = _pct_delta(
        float(primary["avg_hr"]) if primary.get("avg_hr") is not None else None,
        _mean(b_hrs),
    )
    z4_delta = _pct_delta(p_metrics["z4plus_pct"], _mean(b_z4))

    insights: list[str] = _plan_insights(ctx, has_workout=True)
    if plan is None:
        insights.append("no_day_plan")
    data_quality = "good" if len(baseline) >= MIN_BASELINE_SESSIONS else "thin_baseline"
    if data_quality == "thin_baseline":
        insights.append("thin_baseline")

    if strain_delta is not None:
        if strain_delta > STRAIN_DELTA_PCT:
            insights.append("strain_above_baseline")
        elif strain_delta < -STRAIN_DELTA_PCT:
            insights.append("strain_below_baseline")
    if hr_delta is not None and hr_delta > HR_DELTA_PCT:
        insights.append("avg_hr_above_baseline")
    if z4_delta is not None and z4_delta > Z4_DELTA_PCT:
        insights.append("time_in_zone_4_above_baseline")
    if (
        recovery is not None
        and recovery < LOW_RECOVERY_PCT
        and strain_delta is not None
        and strain_delta > STRAIN_DELTA_PCT
    ):
        insights.append("hard_session_on_low_recovery")

    verdict = "typical"
    if strain_delta is not None:
        if strain_delta > STRAIN_DELTA_PCT:
            verdict = "harder_than_usual"
        elif strain_delta < -STRAIN_DELTA_PCT:
            verdict = "easier_than_usual"

    blocks_done = list(plan.get("blocks_done") or []) if plan else []
    if not blocks_done and not (plan and plan.get("is_rest_day")):
        blocks_done = ["metcon"]

    skip_block = {
        "no_day_plan", "thin_baseline", "no_workout_detected",
        "rest_day_planned", "prvn_reference_day", "activity_on_rest_day",
    }
    block_insights = [i for i in insights if i not in skip_block]
    blocks = []
    for kind in blocks_done:
        blocks.append({
            "kind": kind,
            "label": _BLOCK_LABELS.get(kind, kind),
            "metrics": p_metrics,
            "vs_baseline": {
                "strain_pct": strain_delta,
                "avg_hr_pct": hr_delta,
                "z4_minutes_pct": z4_delta,
            },
            "insights": block_insights,
        })

    return _attach_training_context({
        "day": day_key,
        "style": crossfit_style,
        "activity_type": activity_type,
        "primary_workout_id": _workout_row_id(primary),
        "summary": {
            "strain_vs_baseline_pct": strain_delta,
            "avg_hr_vs_baseline_pct": hr_delta,
            "z4plus_vs_baseline_pct": z4_delta,
            "verdict": verdict,
            "recovery_pct": recovery,
            "baseline_session_count": len(baseline),
        },
        "blocks": blocks,
        "insights": insights,
        "data_quality": data_quality,
        "inferred_plan": plan is None,
    }, ctx)
