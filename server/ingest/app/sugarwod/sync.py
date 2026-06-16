"""Map SugarWOD workout payloads to PRVN paste text for PRVNProgramParser."""
from __future__ import annotations

import datetime as dt
import re
from typing import Any

from .client import SugarWODClient

_WEEKDAY_ES = ("LUNES", "MARTES", "MIÉRCOLES", "JUEVES", "VIERNES", "SÁBADO", "DOMINGO")

_SKIP_TITLE_RE = re.compile(
    r"(todo lo que necesitas|informacion de contacto|prvn español\s*:|prvn espanol\s*:)",
    re.I,
)

# Bloques que Rodri no suele hacer — se omiten del import.
_SKIP_BLOCK_RE = re.compile(
    r"(monostructural|recuperacion|recuperación|rest day|natacion|natación|"
    r"^opcion\b|^option\b|recuperacion activa|nivel 1 gimnasia)",
    re.I,
)


def week_start_from_monday_key(week: str) -> dt.date:
    return dt.datetime.strptime(week, "%Y%m%d").date()


def monday_key_for(date: dt.date | None = None) -> str:
    day = date or dt.date.today()
    monday = day - dt.timedelta(days=day.weekday())
    return monday.strftime("%Y%m%d")


def fetch_prvn_week_text(week_monday_yyyymmdd: str, client: SugarWODClient) -> str:
    workouts = client.fetch_workouts_week(week_monday_yyyymmdd)
    if not workouts:
        return ""
    week_start = week_start_from_monday_key(week_monday_yyyymmdd)
    week_end_int = int((week_start + dt.timedelta(days=6)).strftime("%Y%m%d"))
    week_start_int = int(week_monday_yyyymmdd)

    by_day: dict[int, list[dict[str, Any]]] = {i: [] for i in range(7)}
    for w in workouts:
        date_int = _scheduled_date_int(w)
        if date_int is None or not (week_start_int <= date_int <= week_end_int):
            continue
        offset = (dt.datetime.strptime(str(date_int), "%Y%m%d").date() - week_start).days
        if 0 <= offset < 7:
            by_day[offset].append(w)

    lines: list[str] = []
    for offset in range(7):
        day_workouts = _sort_day_workouts(by_day[offset])
        if not day_workouts:
            continue
        day = week_start + dt.timedelta(days=offset)
        lines.append(_WEEKDAY_ES[day.weekday()])
        lines.append(_render_day(day_workouts))
        lines.append("")
    return "\n".join(lines).strip()


def _scheduled_date_int(workout: dict[str, Any]) -> int | None:
    for key in ("scheduledDateInteger", "scheduledDateInt", "dateInt"):
        raw = workout.get(key)
        if raw is None:
            continue
        try:
            return int(raw)
        except (TypeError, ValueError):
            continue
    return None


def _sort_day_workouts(workouts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    order = {"CALENTAMIENTO": 0, "FUERZA": 1, "WOD": 2, "ACCESORIOS": 3}
    return sorted(
        [w for w in workouts if _classify_title(w.get("title") or "") is not None],
        key=lambda w: (
            order.get(_classify_title(w.get("title") or "") or "", 9),
            w.get("whiteboardDisplayOrder") or 0,
        ),
    )


def _render_day(workouts: list[dict[str, Any]]) -> str:
    blocks: dict[str, list[str]] = {
        "CALENTAMIENTO": [],
        "FUERZA": [],
        "WOD": [],
        "ACCESORIOS": [],
    }
    for w in workouts:
        title = (w.get("title") or "").strip()
        kind = _classify_title(title)
        if kind is None:
            continue
        desc = (w.get("description") or "").strip()
        if not desc and title:
            body = title
        elif title and not _title_redundant(title, desc):
            body = f"{title}\n{desc}"
        else:
            body = desc or title
        if body:
            blocks.setdefault(kind, []).append(body)

    out: list[str] = []
    for section in ("CALENTAMIENTO", "FUERZA", "WOD", "ACCESORIOS"):
        if not blocks.get(section):
            continue
        out.append(section)
        out.append("\n\n".join(blocks[section]))
    return "\n\n".join(out)


def _title_redundant(title: str, desc: str) -> bool:
    t = title.strip().lower()
    d = desc.strip().lower()
    return t and (t == d or d.startswith(t.lower()))


def _classify_title(title: str) -> str | None:
    """Map SugarWOD whiteboard titles → bloques que entrenas (sin cardio/recuperación)."""
    t = title.strip()
    if not t or _SKIP_TITLE_RE.search(t):
        return None
    if _SKIP_BLOCK_RE.search(t):
        return None

    low = t.lower()
    if low in {"warmup", "calentamiento"}:
        return "CALENTAMIENTO"
    if low in {
        "fuerza",
        "weightlifting",
        "weigthlifting",
        "snatch pulls",
        "skill",
        "skills",
        "técnica",
        "tecnica",
        "haltero",
        "halterofilia",
    } or "snatch pull" in low:
        return "FUERZA"
    if "accesorio" in low:
        return "ACCESORIOS"
    if low.startswith('"'):
        return "WOD"
    if low in {"acondicionamiento de sabado en parejas"}:
        return "WOD"
    if any(
        k in low
        for k in (
            "amrap",
            "emom",
            "for time",
            "por tiempo",
            "por repeticiones",
            "por calorías",
            "por calorias",
        )
    ):
        return "WOD"
    # Named WODs (Viper, Taipan, …)
    if len(t) <= 36 and t[0] in {'"', "'"}:
        return "WOD"
    if len(t) <= 28 and t[0].isupper() and " " not in t.strip('"'):
        return "WOD"
    return None


def week_to_program_dict(week_monday_yyyymmdd: str, text: str, track_name: str) -> dict[str, Any]:
    """Portable JSON payload for iOS / cache."""
    return {
        "weekStart": _iso_monday(week_monday_yyyymmdd),
        "trackName": track_name,
        "importedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": "sugarwod",
        "pasteText": text,
    }


def _iso_monday(week_yyyymmdd: str) -> str:
    return week_start_from_monday_key(week_yyyymmdd).isoformat()
