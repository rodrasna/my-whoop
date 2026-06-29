"""Personal sleep insights from morning check-ins + strap metrics."""
from __future__ import annotations

import math
import statistics
from typing import Any, Mapping, Sequence

MIN_CHECK_INS = 7
MIN_FACTOR_SAMPLES = 2
MIN_CORRELATION_SAMPLES = 10

_FACTOR_LABELS: dict[str, str] = {
    "heat": "Calor",
    "cold": "Frío",
    "alcohol": "Alcohol",
    "anxiety": "Ansiedad",
    "lateSport": "Actividad intensa tarde",
    "lateDinner": "Cena tarde",
    "stayedUpLate": "Te quedaste despierto tarde",
    "noise": "Ruido",
    "nightWakings": "Despertares",
    "goodTemperature": "Buena temperatura",
    "quiet": "Ambiente silencioso",
    "fellAsleepFast": "Conciliar rápido",
    "feelRecovered": "Sensación de recuperación",
}


def _pearson(xs: Sequence[float], ys: Sequence[float]) -> float | None:
    if len(xs) < MIN_CORRELATION_SAMPLES or len(xs) != len(ys):
        return None
    mx = statistics.fmean(xs)
    my = statistics.fmean(ys)
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den_x = math.sqrt(sum((x - mx) ** 2 for x in xs))
    den_y = math.sqrt(sum((y - my) ** 2 for y in ys))
    if den_x == 0 or den_y == 0:
        return None
    return num / (den_x * den_y)


def _feeling_score(check_in: Mapping[str, Any]) -> float:
    return float(check_in.get("morning_feeling") or 3) * 20.0


def _factors(check_in: Mapping[str, Any]) -> set[str]:
    raw = check_in.get("factors") or []
    if isinstance(raw, str):
        return set()
    return {str(f) for f in raw}


def factor_impacts(
    check_ins: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Mean feeling with vs without each factor."""
    impacts: list[dict[str, Any]] = []
    for factor_id, label in _FACTOR_LABELS.items():
        with_factor: list[float] = []
        without_factor: list[float] = []
        for ci in check_ins:
            feeling = _feeling_score(ci)
            if factor_id in _factors(ci):
                with_factor.append(feeling)
            else:
                without_factor.append(feeling)
        if len(with_factor) < MIN_FACTOR_SAMPLES or len(without_factor) < MIN_FACTOR_SAMPLES:
            continue
        mean_with = statistics.fmean(with_factor)
        mean_without = statistics.fmean(without_factor)
        delta = mean_with - mean_without
        impacts.append({
            "factor_id": factor_id,
            "label": label,
            "delta_feeling": round(delta, 1),
            "count_with": len(with_factor),
            "count_without": len(without_factor),
            "mean_with": round(mean_with, 1),
            "mean_without": round(mean_without, 1),
        })
    impacts.sort(key=lambda x: abs(x["delta_feeling"]), reverse=True)
    return impacts


def metric_correlations(
    check_ins: Sequence[Mapping[str, Any]],
    daily_by_day: Mapping[str, Mapping[str, Any]],
) -> list[dict[str, Any]]:
    feelings: list[float] = []
    efficiencies: list[float] = []
    disturbances: list[float] = []
    deep_mins: list[float] = []
    hrvs: list[float] = []

    for ci in check_ins:
        dk = str(ci["day_key"])
        daily = daily_by_day.get(dk)
        if not daily:
            continue
        feelings.append(_feeling_score(ci))
        if daily.get("efficiency") is not None:
            eff = float(daily["efficiency"])
            efficiencies.append(eff * 100.0 if eff <= 1.0 else eff)
        else:
            efficiencies.append(float("nan"))
        disturbances.append(float(daily.get("disturbances") or 0))
        deep_mins.append(float(daily.get("deep_min") or 0))
        hrvs.append(float(daily.get("avg_hrv") or float("nan")))

    def _pair(metric_vals: list[float], name: str, label: str) -> dict[str, Any] | None:
        pairs = [(f, m) for f, m in zip(feelings, metric_vals) if math.isfinite(m)]
        if len(pairs) < MIN_CORRELATION_SAMPLES:
            return None
        r = _pearson([p[0] for p in pairs], [p[1] for p in pairs])
        if r is None:
            return None
        return {"metric": name, "label": label, "pearson_r": round(r, 2), "n": len(pairs)}

    out: list[dict[str, Any]] = []
    for item in (
        _pair(efficiencies, "efficiency", "Eficiencia"),
        _pair(disturbances, "disturbances", "Despertares detectados"),
        _pair(deep_mins, "deep_min", "Sueño profundo (min)"),
        _pair(hrvs, "avg_hrv", "HRV nocturna"),
    ):
        if item:
            out.append(item)
    out.sort(key=lambda x: abs(x["pearson_r"]), reverse=True)
    return out


def alignment_stats(
    check_ins: Sequence[Mapping[str, Any]],
    daily_by_day: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    aligned = strap_higher = body_higher = 0
    total = 0
    for ci in check_ins:
        dk = str(ci["day_key"])
        daily = daily_by_day.get(dk)
        if not daily:
            continue
        feeling = _feeling_score(ci)
        obj = daily.get("sleep_score_objective")
        if obj is None:
            eff = daily.get("efficiency")
            obj = float(eff) * 100.0 if eff is not None else None
        if obj is None:
            continue
        total += 1
        delta = feeling - float(obj)
        if abs(delta) <= 15:
            aligned += 1
        elif delta < -15:
            strap_higher += 1
        else:
            body_higher += 1
    return {
        "total": total,
        "aligned_pct": round(aligned / total * 100, 1) if total else None,
        "strap_higher_pct": round(strap_higher / total * 100, 1) if total else None,
        "body_higher_pct": round(body_higher / total * 100, 1) if total else None,
    }


def _top_insight_text(
    impacts: list[dict[str, Any]],
    correlations: list[dict[str, Any]],
    alignment: dict[str, Any],
) -> str | None:
    if impacts:
        top = impacts[0]
        delta = top["delta_feeling"]
        if abs(delta) >= 8:
            direction = "mejor" if delta > 0 else "peor"
            return (
                f"Cuando marcas «{top['label']}», tu sensación es ~{abs(int(delta))} pts "
                f"{direction} de media ({top['count_with']} noches)."
            )
    if correlations:
        c = correlations[0]
        if abs(c["pearson_r"]) >= 0.35:
            tie = "sube" if c["pearson_r"] > 0 else "baja"
            return (
                f"Tu sensación suele {tie} cuando {c['label'].lower()} cambia "
                f"(r={c['pearson_r']:+.2f}, {c['n']} mañanas)."
            )
    sh = alignment.get("strap_higher_pct")
    if sh is not None and sh >= 40:
        return (
            f"En el {int(sh)}% de las mañanas la pulsera puntúa mejor sueño "
            "de lo que tú sientes — el cuestionario matutino ajusta el score."
        )
    return None


def build_sleep_insights(
    check_ins: Sequence[Mapping[str, Any]],
    daily_rows: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Aggregate insights for API response."""
    n = len(check_ins)
    if n < MIN_CHECK_INS:
        return {
            "ready": False,
            "check_in_count": n,
            "min_required": MIN_CHECK_INS,
            "message": f"Responde al menos {MIN_CHECK_INS} mañanas para ver patrones personales.",
            "insights": [],
            "top_insight": None,
        }

    daily_by_day = {str(r["day"]): r for r in daily_rows}
    impacts = factor_impacts(check_ins)
    correlations = metric_correlations(check_ins, daily_by_day)
    alignment = alignment_stats(check_ins, daily_by_day)
    top = _top_insight_text(impacts, correlations, alignment)

    insights: list[dict[str, Any]] = []
    if top:
        insights.append({"kind": "summary", "text": top})
    for imp in impacts[:3]:
        if abs(imp["delta_feeling"]) >= 5:
            insights.append({
                "kind": "factor",
                "text": (
                    f"«{imp['label']}»: sensación {imp['mean_with']:.0f}% con vs "
                    f"{imp['mean_without']:.0f}% sin."
                ),
                **imp,
            })

    return {
        "ready": True,
        "check_in_count": n,
        "min_required": MIN_CHECK_INS,
        "top_insight": top,
        "factor_impacts": impacts[:8],
        "correlations": correlations,
        "alignment": alignment,
        "insights": insights,
    }
