"""Parse a morning voice/text sleep check-in and contrast with strap metrics.

Rules-first (no API key required). Optional OpenAI refinement when
``OPENAI_API_KEY`` is set — never overwrites numeric strap values.
"""
from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from dataclasses import dataclass

# factor_id → Spanish keyword stems (lowercase substring match)
_FACTOR_KEYWORDS: dict[str, tuple[str, ...]] = {
    "heat": ("calor", "caluro", "bochorn", "sofoc"),
    "cold": ("frío", "frio", "helad", "tembl"),
    "alcohol": ("alcohol", "cerveza", "vino", "copa", "borrach", "bebí", "bebi"),
    "anxiety": ("ansiedad", "ansios", "nervios", "preocup", "estrés", "estres", "angust"),
    "lateSport": ("crossfit", "entreno", "entren", "deporte", "gym", "correr", "wod", "pesas"),
    "lateDinner": ("cena tarde", "cené tarde", "cene tarde", "comí tarde", "comi tarde",
                   "digestión", "digestion", "cena pesada", "comida tarde"),
    "stayedUpLate": ("despierto tarde", "me quedé", "me quede", "madrug", "pantalla",
                     "netflix", "móvil", "movil", "instagram", "tarde en la cama"),
    "noise": ("ruido", "ruidos", "vecino", "tráfico", "trafico", "camion", "camión"),
    "nightWakings": ("desperté", "desperte", "me despert", "despertar", "interrup",
                     "me levanté a las", "me levante a las"),
    "goodTemperature": ("temperatura bien", "temperatura agradable", "ni frío", "ni calor",
                        "fresco", "clima bien"),
    "quiet": ("silencio", "silencioso", "tranquilo", "callado", "sin ruido"),
    "fellAsleepFast": ("rápido dorm", "rapido dorm", "enseguida", "al momento", "fácil dorm",
                       "facil dorm", "en nada"),
    "feelRecovered": ("recuperado", "descansado", "con energía", "con energia", "fresco al levant"),
}

_FEELING_PATTERNS: list[tuple[int, tuple[str, ...]]] = [
    (1, ("fatal", "horrible", "pésim", "pesim", "muy mal", "desastre")),
    (2, ("mal dorm", "cansad", "agotad", "mal ", "flojo", "destrozad")),
    (5, ("genial", "increíble", "increible", "perfecto", "muy bien", "excelente")),
    (4, ("bien dorm", "bastante bien", "dormí bien", "dormi bien", "bien ")),
    (3, ("regular", "normal", "más o menos", "mas o menos", "aceptable")),
]

_ONSET_HARD = ("costó dorm", "costo dorm", "tardé en dorm", "tarde en dorm", "insomnio",
               "no podía dorm", "no podia dorm", "dar vueltas", "dar mil vueltas")
_ONSET_EASY = ("rápido dorm", "rapido dorm", "fácil dorm", "facil dorm", "enseguida",
               "al momento", "en nada", "sin problema")


@dataclass(frozen=True)
class SleepCheckInAnalysis:
    sleep_quality_summary: str
    perceived_causes: list[str]
    subjective_recovery_pct: float | None
    strap_recovery_pct: float | None
    alignment: str
    conclusion: str
    morning_feeling: int
    onset: str
    factors: list[str]

    def as_dict(self) -> dict:
        return {
            "sleep_quality_summary": self.sleep_quality_summary,
            "perceived_causes": self.perceived_causes,
            "subjective_recovery_pct": self.subjective_recovery_pct,
            "strap_recovery_pct": self.strap_recovery_pct,
            "alignment": self.alignment,
            "conclusion": self.conclusion,
            "morning_feeling": self.morning_feeling,
            "onset": self.onset,
            "factors": self.factors,
        }


def _norm(text: str) -> str:
    return text.lower().strip()


def _match_any(text: str, stems: tuple[str, ...]) -> bool:
    return any(s in text for s in stems)


def detect_factors(text: str) -> list[str]:
    found: list[str] = []
    for factor_id, stems in _FACTOR_KEYWORDS.items():
        if _match_any(text, stems):
            found.append(factor_id)
    return found


def infer_morning_feeling(text: str) -> int:
    for score, stems in _FEELING_PATTERNS:
        if _match_any(text, stems):
            return score
    return 3


def infer_onset(text: str) -> str:
    if _match_any(text, _ONSET_HARD):
        return "hard"
    if _match_any(text, _ONSET_EASY):
        return "easy"
    return "normal"


def subjective_recovery_pct(morning_feeling: int) -> float:
    return float(morning_feeling * 20)


def strap_recovery_pct_value(recovery_pct: float | None) -> float | None:
    if recovery_pct is None:
        return None
    return recovery_pct * 100.0 if recovery_pct <= 1.0 else recovery_pct


def compute_alignment(subjective: float | None, strap: float | None) -> str:
    if subjective is None or strap is None:
        return "unknown"
    delta = subjective - strap
    if abs(delta) <= 15:
        return "aligned"
    if delta < -15:
        return "strap_higher"
    return "body_higher"


def _extract_causes(text: str, factors: list[str]) -> list[str]:
    """Short human phrases for detected factors + 'porque' clauses."""
    labels = {
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
    causes = [labels.get(f, f) for f in factors]
    for m in re.finditer(r"porque\s+([^.,;]+)", text, flags=re.IGNORECASE):
        phrase = m.group(1).strip()
        if phrase and phrase not in causes:
            causes.append(phrase[:80])
    return causes[:6]


def _build_conclusion(
    feeling: int,
    subjective: float | None,
    strap: float | None,
    alignment: str,
    factors: list[str],
) -> str:
    feeling_word = {1: "muy mal", 2: "mal", 3: "regular", 4: "bien", 5: "muy bien"}.get(feeling, "regular")
    parts = [f"Te levantas {feeling_word}."]
    if factors:
        neg = [f for f in factors if f not in ("goodTemperature", "quiet", "fellAsleepFast", "feelRecovered")]
        pos = [f for f in factors if f in ("goodTemperature", "quiet", "fellAsleepFast", "feelRecovered")]
        if neg:
            parts.append("Posibles causas: " + ", ".join(neg[:3]) + ".")
        if pos:
            parts.append("Lo que ayudó: " + ", ".join(pos[:3]) + ".")
    if alignment == "aligned" and subjective is not None and strap is not None:
        parts.append(
            f"Tu sensación (~{int(subjective)}%) encaja con recovery de la pulsera ({int(strap)}%)."
        )
    elif alignment == "strap_higher" and subjective is not None and strap is not None:
        parts.append(
            f"La pulsera marca recovery {int(strap)}% pero tu cuerpo dice ~{int(subjective)}% "
            "— confía en cómo te sientes; los datos objetivos no lo capturan todo."
        )
    elif alignment == "body_higher" and subjective is not None and strap is not None:
        parts.append(
            f"Te sientes mejor (~{int(subjective)}%) que el recovery de la pulsera ({int(strap)}%). "
            "Puede que la noche haya sido reparadora aunque las métricas no lo reflejen del todo."
        )
    else:
        parts.append("Tu sensación es tan válida como las métricas de la pulsera.")
    return " ".join(parts)


def analyze_transcript(
    transcript: str,
    *,
    recovery_pct: float | None = None,
    sleep_efficiency_pct: float | None = None,
) -> SleepCheckInAnalysis:
    """Rule-based parse of free-text / voice transcript."""
    text = _norm(transcript)
    if not text:
        raise ValueError("transcript is empty")

    feeling = infer_morning_feeling(text)
    onset = infer_onset(text)
    factors = detect_factors(text)
    subjective = subjective_recovery_pct(feeling)
    strap = strap_recovery_pct_value(recovery_pct)
    alignment = compute_alignment(subjective, strap)
    causes = _extract_causes(text, factors)

    summary = transcript.strip()
    if len(summary) > 160:
        summary = summary[:157] + "…"

    conclusion = _build_conclusion(feeling, subjective, strap, alignment, factors)
    if sleep_efficiency_pct is not None and sleep_efficiency_pct < 75 and feeling <= 2:
        conclusion += f" Eficiencia de sueño {int(sleep_efficiency_pct)}% — coherente con sensación baja."

    return SleepCheckInAnalysis(
        sleep_quality_summary=summary,
        perceived_causes=causes,
        subjective_recovery_pct=subjective,
        strap_recovery_pct=strap,
        alignment=alignment,
        conclusion=conclusion,
        morning_feeling=feeling,
        onset=onset,
        factors=factors,
    )


def maybe_refine_with_llm(analysis: SleepCheckInAnalysis, transcript: str) -> SleepCheckInAnalysis:
    """Optional OpenAI pass for richer Spanish narrative; keeps structured fields."""
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        return analysis

    prompt = (
        "Eres un asistente de sueño. Dado el texto del usuario y el análisis estructurado, "
        "devuelve SOLO JSON con keys: sleep_quality_summary, perceived_causes (array), "
        "conclusion (2-3 frases en español, contrasta sensación vs pulsera). "
        "No inventes números distintos a los del análisis.\n\n"
        f"Texto: {transcript}\n"
        f"Análisis: {json.dumps(analysis.as_dict(), ensure_ascii=False)}"
    )
    body = json.dumps({
        "model": os.environ.get("OPENAI_MODEL", "gpt-4o-mini"),
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.3,
        "response_format": {"type": "json_object"},
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
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read())
        content = payload["choices"][0]["message"]["content"]
        refined = json.loads(content)
        return SleepCheckInAnalysis(
            sleep_quality_summary=refined.get("sleep_quality_summary", analysis.sleep_quality_summary),
            perceived_causes=refined.get("perceived_causes", analysis.perceived_causes),
            subjective_recovery_pct=analysis.subjective_recovery_pct,
            strap_recovery_pct=analysis.strap_recovery_pct,
            alignment=analysis.alignment,
            conclusion=refined.get("conclusion", analysis.conclusion),
            morning_feeling=analysis.morning_feeling,
            onset=analysis.onset,
            factors=analysis.factors,
        )
    except (urllib.error.URLError, KeyError, json.JSONDecodeError, IndexError):
        return analysis
