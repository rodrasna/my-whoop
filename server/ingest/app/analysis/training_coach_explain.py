"""Optional LLM narrative for training coach reports (task-09 Phase B)."""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

_MAX_WORDS = 120

_PHRASES_ES: dict[str, str] = {
    "strain_above_baseline": "El strain quedó por encima de tu media en sesiones comparables.",
    "strain_below_baseline": "El strain fue más bajo que tu habitual en este tipo de sesión.",
    "avg_hr_above_baseline": "La FC media fue más alta de lo habitual — ritmo exigente.",
    "time_in_zone_4_above_baseline": "Pasaste más tiempo en zona 4–5 que de costumbre; pacing agresivo.",
    "hard_session_on_low_recovery": "Llegaste con poca recuperación y aun así la sesión fue dura.",
    "no_workout_detected": "No hay un bout de entreno claro para analizar este día.",
    "rest_day_planned": "Tenías descanso planificado; no se esperaba entreno.",
    "activity_on_rest_day": "Entrenaste aunque el día estaba marcado como descanso.",
    "prvn_reference_day": "El programa de referencia venía de otro día PRVN.",
}


def deterministic_narrative(report: dict[str, Any]) -> str:
    """Template fallback when LLM is unavailable (same facts as insight IDs)."""
    parts: list[str] = []
    verdict = (report.get("summary") or {}).get("verdict")
    if verdict == "harder_than_usual":
        parts.append("Hoy fue más duro de lo habitual.")
    elif verdict == "easier_than_usual":
        parts.append("Hoy fue más ligero de lo habitual.")
    elif verdict == "typical":
        parts.append("El rendimiento estuvo dentro de tu rango habitual.")
    elif verdict == "rest_day":
        parts.append("Tenías descanso planificado este día.")

    ctx = report.get("training_context") or {}
    if ctx.get("user_note"):
        parts.append(f"Nota del día: {ctx['user_note']}")
    if ref := ctx.get("prvn_reference_day_key"):
        parts.append(f"Programa de referencia: {ref}.")

    if report.get("inferred_plan"):
        parts.append("No había plan del día sincronizado; el análisis usa solo el bout detectado.")

    for iid in report.get("insights") or []:
        if phrase := _PHRASES_ES.get(iid):
            parts.append(phrase)

    if not parts:
        parts.append("Sin comparativa clara con tu histórico reciente.")
    return " ".join(parts)


def _trim_words(text: str, limit: int = _MAX_WORDS) -> str:
    words = text.split()
    if len(words) <= limit:
        return text.strip()
    return " ".join(words[:limit]).strip() + "…"


def explain_with_llm(report: dict[str, Any], *, note: str | None = None) -> str | None:
    """Call OpenAI when configured; return None on missing key or failure."""
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        return None

    report_for_prompt = dict(report)
    if note:
        report_for_prompt["user_note"] = note

    prompt = (
        "Eres un coach de CrossFit. Escribe un párrafo breve en español (máximo 120 palabras). "
        "SOLO usa números y hechos presentes en el JSON. No inventes métricas ni RPE. "
        "No des consejos médicos. Tono directo y útil.\n\n"
        f"JSON:\n{json.dumps(report_for_prompt, ensure_ascii=False)}"
    )
    body = json.dumps({
        "model": os.environ.get("OPENAI_MODEL", "gpt-4o-mini"),
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.35,
        "max_tokens": 220,
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            payload = json.loads(resp.read())
        content = payload["choices"][0]["message"]["content"]
        return _trim_words(str(content).strip())
    except (urllib.error.URLError, KeyError, json.JSONDecodeError, IndexError, TypeError):
        return None


def explain_report(
    report: dict[str, Any],
    *,
    include_note: bool = False,
    note: str | None = None,
) -> tuple[str, str]:
    """Return ``(narrative, source)`` where source is ``llm`` or ``template``."""
    safe_note = note.strip() if include_note and note else None
    llm_text = explain_with_llm(report, note=safe_note)
    if llm_text:
        return llm_text, "llm"
    return deterministic_narrative(report), "template"
