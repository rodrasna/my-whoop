"""FastAPI ingest service. Bearer-auth write endpoint + health check + read API +
the static datastore dashboard."""
import datetime as _dt
import logging
import os
import threading
import time

import psycopg
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import db, ingest, read, store
from .analysis import daily
from .analysis import training_coach
from .analysis import training_coach_explain
from .analysis.sleep_check_in import analyze_transcript, maybe_refine_with_llm
from .config import load_config
from .sugarwod import service as sugarwod_service
from .sugarwod.client import SugarWODError

_log = logging.getLogger("whoop.ingest")

cfg = load_config()
db.bootstrap_schema(cfg.db_dsn)

# Docs/schema disabled: don't advertise the API surface publicly (every /v1 route is
# Bearer-gated, but the OpenAPI schema + Swagger UI were world-readable).
app = FastAPI(title="Whoop Ingest", docs_url=None, redoc_url=None, openapi_url=None)

_STATIC = os.path.join(os.path.dirname(__file__), "static")
app.mount("/static", StaticFiles(directory=_STATIC), name="static")

# --- Auto-recompute throttle -------------------------------------------------
# The phone uploads opportunistically (every ~30s while connected, plus backlog
# drains), so /v1/ingest-decoded can fire many times per minute — each touching
# the SAME current day. compute_day now runs the heavy neurokit sleep-staging
# pipeline, so recomputing a day on every upload saturates CPU/memory. We
# therefore (a) single-flight recomputes (never run two at once) and (b) debounce
# per (device, day) so a day recomputes at most once per cooldown. On-demand
# freshness is always available via POST /v1/compute-daily.
_RECOMPUTE_COOLDOWN_S = 120.0
_recompute_lock = threading.Lock()
_last_recompute: dict[tuple[str, _dt.date], float] = {}


@app.get("/")
def dashboard():
    """Serve the datastore dashboard (static SPA reading the /v1 read API)."""
    return FileResponse(os.path.join(_STATIC, "index.html"))


@app.get("/architecture")
def architecture():
    """Serve the device-link architecture page (how we talk to the strap, no byte detail)."""
    return FileResponse(os.path.join(_STATIC, "architecture.html"))


def require_auth(authorization: str = Header(default="")) -> None:
    expected = f"Bearer {cfg.api_key}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="unauthorized")


class Frame(BaseModel):
    seq: int | None = None
    hex: str


class ClockRef(BaseModel):
    device: int
    wall: int


class Device(BaseModel):
    device_id: str
    mac: str | None = None
    name: str | None = None


class IngestBatch(BaseModel):
    batch_id: str
    device: Device
    clock_ref: ClockRef
    frames: list[Frame]
    decode_streams: bool = True


# ── Decoded-upload models ────────────────────────────────────────────────────

class DecodedDevice(BaseModel):
    id: str
    mac: str | None = None
    name: str | None = None


class DecodedStreams(BaseModel):
    hr: list[dict] = []
    rr: list[dict] = []
    events: list[dict] = []
    battery: list[dict] = []
    # Type-47 V24 biometric history (optional; older clients omit these). Values are
    # raw ADC for spo2/skin_temp/resp; gravity is the accel-derived vector in g.
    spo2: list[dict] = []
    skin_temp: list[dict] = []
    resp: list[dict] = []
    gravity: list[dict] = []


class DecodedBatch(BaseModel):
    device: DecodedDevice
    streams: DecodedStreams


@app.get("/healthz")
def healthz():
    try:
        with psycopg.connect(cfg.db_dsn, connect_timeout=3) as conn:
            conn.execute("SELECT 1")
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"db unavailable: {e}")


@app.post("/v1/ingest", dependencies=[Depends(require_auth)])
def ingest_batch(batch: IngestBatch):
    payload = batch.model_dump()
    with psycopg.connect(cfg.db_dsn) as conn:
        result = ingest.process_batch(conn, cfg, payload)
        conn.commit()
    return result


def _batch_dates_utc(streams: dict) -> set[_dt.date]:
    """UTC calendar dates spanned by every stream-row ts in an ingest batch."""
    days: set[_dt.date] = set()
    for rows in streams.values():
        for r in rows or []:
            ts = r.get("ts")
            if ts is None:
                continue
            days.add(_dt.datetime.fromtimestamp(float(ts), _dt.timezone.utc).date())
    return days


@app.post("/v1/ingest-decoded", dependencies=[Depends(require_auth)])
def ingest_decoded(batch: DecodedBatch):
    payload = batch.model_dump()
    device_id = payload["device"]["id"]
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, device_id,
                            mac=payload["device"].get("mac"),
                            name=payload["device"].get("name"))
        counts = store.upsert_streams(conn, device_id, payload["streams"])
        conn.commit()
        # Recompute the day(s) this batch touched — throttled (see _RECOMPUTE_*).
        # Best-effort: a compute error must NOT fail the ingest (the raw streams
        # are already persisted) — log + move on.
        for day in _batch_dates_utc(payload["streams"]):
            key = (device_id, day)
            if time.monotonic() - _last_recompute.get(key, 0.0) < _RECOMPUTE_COOLDOWN_S:
                continue  # debounce: this day was recomputed very recently
            if not _recompute_lock.acquire(blocking=False):
                continue  # single-flight: a recompute is already running; a later upload catches up
            try:
                daily.compute_day(conn, device_id, day)
                conn.commit()
            except Exception:
                conn.rollback()
                _log.exception("compute_day failed for %s %s (ingest still 200)", device_id, day)
            finally:
                _last_recompute[key] = time.monotonic()  # throttle successes AND failures
                _recompute_lock.release()
    return {"upserted": counts}


@app.get("/v1/devices", dependencies=[Depends(require_auth)])
def get_devices():
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.list_devices(conn)


@app.get("/v1/batches", dependencies=[Depends(require_auth)])
def get_batches(device: str, limit: int = 100):
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.list_batches(conn, device_id=device, limit=limit)


@app.get("/v1/summary", dependencies=[Depends(require_auth)])
def get_summary(device: str,
                from_: int = Query(0, alias="from"),
                to: int = Query(2_000_000_000, alias="to")):
    """Exact (unlimited) counts per decoded stream + raw batches, for accurate dashboard totals."""
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.counts(conn, device_id=device, start=from_, end=to)


@app.get("/v1/streams/{kind}", dependencies=[Depends(require_auth)])
def get_stream(kind: str, device: str,
               from_: int = Query(0, alias="from"),
               to: int = Query(2_000_000_000, alias="to"),
               limit: int = 5000,
               max_points: int | None = None):
    try:
        with psycopg.connect(cfg.db_dsn) as conn:
            return read.query_stream(conn, kind, device_id=device, start=from_, end=to,
                                     limit=limit, max_points=max_points)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"unknown stream kind: {kind}")


@app.get("/v1/resp-series", dependencies=[Depends(require_auth)])
def get_resp_series(device: str,
                    from_: int = Query(0, alias="from"),
                    to: int = Query(2_000_000_000, alias="to")):
    """RSA-derived respiratory-rate trend (BrPM over time) from the RR series in
    [from, to] (unix seconds). Returns [{ts, value, unit}]; empty when too few beats."""
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_resp_series(conn, device_id=device, start=from_, end=to)


@app.get("/v1/temp-series", dependencies=[Depends(require_auth)])
def get_temp_series(device: str,
                    from_: int = Query(0, alias="from"),
                    to: int = Query(2_000_000_000, alias="to")):
    """Skin-temperature deviation trend (Δ°C from nightly median) from the
    skin_temp_samples table in [from, to] (unix seconds).
    Returns [{ts, value, unit}] where unit="Δ°C"; empty when no rows in window.
    Values are relative to the within-night median raw ADC — NOT absolute °C."""
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_temp_series(conn, device_id=device, start=from_, end=to)


@app.get("/v1/spo2-series", dependencies=[Depends(require_auth)])
def get_spo2_series(device: str,
                    from_: int = Query(0, alias="from"),
                    to: int = Query(2_000_000_000, alias="to")):
    """Windowed SpO₂ TREND (%) from the spo2_samples table in [from, to] (unix seconds).
    Returns [{ts, value, unit}] where unit="%"; empty when no rows or all windows are
    rejected by the perfusion quality gate (motion artefact, flat signal, off-wrist).
    APPROXIMATION — ratio-of-ratios estimator, NOT calibrated; useful as a relative trend only."""
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_spo2_series(conn, device_id=device, start=from_, end=to)


# ── Daily analysis endpoints (Task 2.5) ──────────────────────────────────────

class ComputeDaily(BaseModel):
    device: str
    date: str  # YYYY-MM-DD


def _parse_date(s: str) -> _dt.date:
    try:
        return _dt.date.fromisoformat(s)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"invalid date (want YYYY-MM-DD): {s!r}")


@app.post("/v1/compute-daily", dependencies=[Depends(require_auth)])
def compute_daily(body: ComputeDaily):
    """Compute + persist the daily metrics for a device/date, returning the summary."""
    day = _parse_date(body.date)
    with psycopg.connect(cfg.db_dsn) as conn:
        result = daily.compute_day(conn, body.device, day)
        conn.commit()
    return result


@app.get("/v1/daily", dependencies=[Depends(require_auth)])
def get_daily(device: str,
              from_: str = Query(..., alias="from"),
              to: str = Query(..., alias="to")):
    """daily_metrics rows over the inclusive [from, to] date range (YYYY-MM-DD)."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_daily(conn, device, start, end)


@app.get("/v1/sleep", dependencies=[Depends(require_auth)])
def get_sleep(device: str, date: str):
    """Sleep sessions whose night ENDS on ``date`` (YYYY-MM-DD)."""
    day = _parse_date(date)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_sleep(conn, device, day)


@app.delete("/v1/sleep/session", dependencies=[Depends(require_auth)])
def delete_sleep_session(device: str, start_ts: float):
    """Remove one erroneous sleep session (PK = device + start_ts epoch seconds)."""
    with psycopg.connect(cfg.db_dsn) as conn:
        deleted = store.delete_sleep_session(conn, device, start_ts)
        conn.commit()
    if deleted == 0:
        raise HTTPException(status_code=404, detail="sleep session not found")
    return {"deleted": deleted, "device": device, "start_ts": start_ts}


# ── Profile endpoints ─────────────────────────────────────────────────────────

_VALID_SEX = {"male", "female", "nonbinary"}


class ProfileBody(BaseModel):
    device: str
    height_cm: float | None = None
    weight_kg: float | None = None
    age: int | None = None
    sex: str | None = None


@app.get("/v1/profile", dependencies=[Depends(require_auth)])
def get_profile(device: str):
    """Return the stored profile for a device, or {} if none exists."""
    with psycopg.connect(cfg.db_dsn) as conn:
        row = read.query_profile(conn, device)
    return row or {}


@app.post("/v1/profile", dependencies=[Depends(require_auth)])
def upsert_profile(body: ProfileBody):
    """Create or update the user profile (height/weight/age/sex) for a device."""
    sex = body.sex
    if sex is not None:
        sex = sex.lower().strip()
        if sex not in _VALID_SEX:
            raise HTTPException(
                status_code=422,
                detail=f"sex must be one of {sorted(_VALID_SEX)} or null; got {body.sex!r}",
            )
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, body.device)
        store.upsert_profile(conn, body.device,
                             height_cm=body.height_cm,
                             weight_kg=body.weight_kg,
                             age=body.age,
                             sex=sex)
        conn.commit()
        row = read.query_profile(conn, body.device)
    return row


# ── Sleep check-in (subjective morning questionnaire) ─────────────────────────

_VALID_ONSET = {"easy", "normal", "hard"}


class SleepCheckInBody(BaseModel):
    device: str
    day_key: str
    morning_feeling: int = Field(ge=1, le=5)
    onset: str
    factors: list[str] = []
    note: str | None = None
    saved_at: float  # epoch seconds
    recovery_pct: float | None = None
    sleep_efficiency_pct: float | None = None
    voice_transcript: str | None = None
    analysis: dict | None = None


class SleepCheckInAnalyzeBody(BaseModel):
    device: str
    day_key: str
    transcript: str = Field(min_length=1)
    recovery_pct: float | None = None
    sleep_efficiency_pct: float | None = None


@app.get("/v1/sleep-check-ins", dependencies=[Depends(require_auth)])
def get_sleep_check_ins(device: str,
                        from_: str = Query(..., alias="from"),
                        to: str = Query(..., alias="to")):
    """Subjective sleep check-ins over inclusive [from, to] day_key range."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        rows = read.query_sleep_check_ins(conn, device, start, end)
    return rows


@app.post("/v1/sleep-check-in", dependencies=[Depends(require_auth)])
def post_sleep_check_in(body: SleepCheckInBody):
    """Upsert one morning check-in for a wake day."""
    onset = body.onset.lower().strip()
    if onset not in _VALID_ONSET:
        raise HTTPException(
            status_code=422,
            detail=f"onset must be one of {sorted(_VALID_ONSET)}; got {body.onset!r}",
        )
    row = {
        "day_key": body.day_key,
        "morning_feeling": body.morning_feeling,
        "onset": onset,
        "factors": body.factors,
        "note": body.note,
        "saved_at": body.saved_at,
        "recovery_pct": body.recovery_pct,
        "sleep_efficiency_pct": body.sleep_efficiency_pct,
        "voice_transcript": body.voice_transcript,
        "analysis": body.analysis,
    }
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, body.device)
        store.upsert_sleep_check_in(conn, body.device, row)
        conn.commit()
        rows = read.query_sleep_check_ins(conn, body.device, body.day_key, body.day_key)
    return rows[0] if rows else row


@app.post("/v1/sleep-check-in/analyze", dependencies=[Depends(require_auth)])
def analyze_sleep_check_in(body: SleepCheckInAnalyzeBody):
    """Parse voice/text transcript; contrast subjective feeling with strap metrics."""
    transcript = body.transcript.strip()
    if not transcript:
        raise HTTPException(status_code=422, detail="transcript is required")
    try:
        base = analyze_transcript(
            transcript,
            recovery_pct=body.recovery_pct,
            sleep_efficiency_pct=body.sleep_efficiency_pct,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    refined = maybe_refine_with_llm(base, transcript)
    payload = refined.as_dict()
    payload["voice_transcript"] = transcript
    payload["day_key"] = body.day_key
    return payload


# ── PRVN / SugarWOD programming ─────────────────────────────────────────────

class PRVNSyncBody(BaseModel):
    device: str
    week: str | None = None  # Monday YYYYMMDD; default = current week


@app.get("/v1/prvn/week", dependencies=[Depends(require_auth)])
def get_prvn_week(device: str):
    """Cached PRVN week (paste text + metadata) synced from SugarWOD."""
    payload = sugarwod_service.load_cached(cfg.raw_root, device)
    if not payload:
        raise HTTPException(status_code=404, detail="no PRVN week cached; POST /v1/prvn/sync first")
    return payload


@app.post("/v1/prvn/sync", dependencies=[Depends(require_auth)])
def post_prvn_sync(body: PRVNSyncBody):
    """Login to SugarWOD (server credentials) and refresh the PRVN week cache."""
    if not sugarwod_service.sugarwod_configured():
        raise HTTPException(status_code=503, detail="SugarWOD credentials not configured on server")
    week = body.week
    if week is not None and (len(week) != 8 or not week.isdigit()):
        raise HTTPException(status_code=400, detail="week must be YYYYMMDD (Monday)")
    try:
        with psycopg.connect(cfg.db_dsn) as conn:
            store.ensure_device(conn, body.device)
            conn.commit()
        return sugarwod_service.sync_week(
            raw_root=cfg.raw_root,
            device_id=body.device,
            week_monday_yyyymmdd=week,
        )
    except SugarWODError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


# ── Workouts endpoint ─────────────────────────────────────────────────────────

@app.get("/v1/workouts", dependencies=[Depends(require_auth)])
def get_workouts(device: str,
                 from_: str | None = Query(None, alias="from"),
                 to: str | None = Query(None, alias="to"),
                 from_ts: int | None = Query(None, alias="from_ts"),
                 to_ts: int | None = Query(None, alias="to_ts")):
    """Exercise sessions for a device.

    Either pass ``from``/``to`` (YYYY-MM-DD, UTC calendar date of start_ts) or
    ``from_ts``/``to_ts`` (unix seconds, half-open [from_ts, to_ts)) for local-day
    windows from the app.
    """
    with psycopg.connect(cfg.db_dsn) as conn:
        if from_ts is not None and to_ts is not None:
            return read.query_workouts_epoch(conn, device, float(from_ts), float(to_ts))
        if from_ is None or to is None:
            raise HTTPException(status_code=422, detail="provide from/to (dates) or from_ts/to_ts")
        start, end = _parse_date(from_), _parse_date(to)
        return read.query_workouts(conn, device, start, end)


@app.get("/v1/stress", dependencies=[Depends(require_auth)])
def get_stress(device: str,
               from_: str = Query(..., alias="from"),
               to: str = Query(..., alias="to")):
    """Intraday stress windows (5-min) for dates in [from, to] inclusive (YYYY-MM-DD)."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        rows = read.query_stress_samples(conn, device, start, end)
    out = []
    for r in rows:
        ts = r["ts"]
        if isinstance(ts, (int, float)):
            iso = _dt.datetime.fromtimestamp(ts, _dt.timezone.utc).isoformat()
        else:
            iso = ts.isoformat() if hasattr(ts, "isoformat") else ts
        out.append({
            "ts": iso,
            "score": r.get("score"),
            "rmssd_ms": r.get("rmssd_ms"),
            "hr_bpm": r.get("hr_bpm"),
            "motion_var": r.get("motion_var"),
            "quality": r.get("quality"),
        })
    return out


# ── Coach sync (day plan + mobility completions) ─────────────────────────────

_VALID_ACTIVITY_TYPES = frozenset({
    "crossfit", "running", "cycling", "strength", "hiit", "walking",
    "swimming", "rowing", "yoga", "cardio", "other",
})

_VALID_CROSSFIT_STYLES = frozenset({
    "regular", "qualifier", "benchmark", "hero", "skill", "partner",
})


class DayPlanBody(BaseModel):
    device: str
    day: str
    primary_workout_id: str | None = None
    activity_type: str | None = None
    crossfit_style: str | None = None
    blocks_done: list[str] = []
    note: str | None = None
    prvn_reference_day_key: str | None = None
    is_rest_day: bool = False
    saved_at: float | None = None


class MobilityCompletionBody(BaseModel):
    device: str
    day_key: str
    session_kind: str
    exercise_count: int = Field(ge=0)
    completed_at: float


@app.put("/v1/day-plan", dependencies=[Depends(require_auth)])
def put_day_plan(body: DayPlanBody):
    """Upsert the manual workout day plan for coach context."""
    if body.activity_type is not None and body.activity_type not in _VALID_ACTIVITY_TYPES:
        raise HTTPException(status_code=422, detail=f"invalid activity_type: {body.activity_type!r}")
    if body.crossfit_style is not None and body.crossfit_style not in _VALID_CROSSFIT_STYLES:
        raise HTTPException(status_code=422, detail=f"invalid crossfit_style: {body.crossfit_style!r}")
    if body.prvn_reference_day_key is not None:
        try:
            _dt.date.fromisoformat(body.prvn_reference_day_key)
        except ValueError:
            raise HTTPException(
                status_code=422,
                detail=f"invalid prvn_reference_day_key: {body.prvn_reference_day_key!r}",
            )
    bad_blocks = [b for b in body.blocks_done if b not in read._VALID_PROGRAM_BLOCK_KINDS]
    if bad_blocks:
        raise HTTPException(status_code=422, detail=f"invalid blocks_done: {bad_blocks}")
    saved_at = body.saved_at if body.saved_at is not None else time.time()
    row = {
        "day_key": body.day,
        "primary_workout_id": body.primary_workout_id,
        "activity_type": body.activity_type,
        "crossfit_style": body.crossfit_style,
        "blocks_done": body.blocks_done,
        "note": body.note,
        "prvn_reference_day_key": body.prvn_reference_day_key,
        "is_rest_day": body.is_rest_day,
        "saved_at": saved_at,
    }
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, body.device)
        store.upsert_workout_day_plan(conn, body.device, row)
        conn.commit()
        rows = read.query_workout_day_plans(conn, body.device, body.day, body.day)
    return rows[0] if rows else row


@app.delete("/v1/day-plan", dependencies=[Depends(require_auth)])
def delete_day_plan(device: str, day: str):
    """Remove a manual day plan (user cleared the editor)."""
    with psycopg.connect(cfg.db_dsn) as conn:
        store.delete_workout_day_plan(conn, device, day)
        conn.commit()
    return {"status": "deleted", "device": device, "day": day}


@app.get("/v1/day-plans", dependencies=[Depends(require_auth)])
def get_day_plans(device: str,
                  from_: str = Query(..., alias="from"),
                  to: str = Query(..., alias="to")):
    """Manual day plans over inclusive [from, to] day_key range (YYYY-MM-DD)."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_workout_day_plans(conn, device, start, end)


@app.post("/v1/mobility-completion", dependencies=[Depends(require_auth)])
def post_mobility_completion(body: MobilityCompletionBody):
    """Upsert one guided mobility session completion."""
    if body.session_kind not in read._VALID_MOBILITY_SESSION_KINDS:
        raise HTTPException(
            status_code=422,
            detail=f"session_kind must be one of {sorted(read._VALID_MOBILITY_SESSION_KINDS)}; "
                   f"got {body.session_kind!r}",
        )
    row = {
        "day_key": body.day_key,
        "session_kind": body.session_kind,
        "exercise_count": body.exercise_count,
        "completed_at": body.completed_at,
    }
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, body.device)
        store.upsert_mobility_completion(conn, body.device, row)
        conn.commit()
        rows = read.query_mobility_completions(conn, body.device, body.day_key, body.day_key)
    return rows[0] if rows else row


@app.get("/v1/mobility-completions", dependencies=[Depends(require_auth)])
def get_mobility_completions(device: str,
                             from_: str = Query(..., alias="from"),
                             to: str = Query(..., alias="to")):
    """Mobility completions over inclusive [from, to] day_key range (YYYY-MM-DD)."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_mobility_completions(conn, device, start, end)


# ── Training coach (deterministic report) ─────────────────────────────────────

@app.get("/v1/coach/day", dependencies=[Depends(require_auth)])
def get_coach_day(device: str, day: str):
    """Cached training-day coach report (JSON). 404 if not computed yet."""
    with psycopg.connect(cfg.db_dsn) as conn:
        row = read.query_coach_report(conn, device, day)
    if row is None:
        raise HTTPException(status_code=404, detail="no coach report for this day; POST to compute")
    return row["report"]


@app.post("/v1/coach/day", dependencies=[Depends(require_auth)])
def post_coach_day(device: str, day: str):
    """Compute and cache a deterministic training-day coach report."""
    _parse_date(day)  # validate YYYY-MM-DD
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, device)
        report = training_coach.compute_day_report(conn, device, day)
        store.upsert_coach_report(conn, device, day, report)
        conn.commit()
    return report


class CoachExplainBody(BaseModel):
    device: str
    day: str
    include_note: bool = False


@app.post("/v1/coach/explain", dependencies=[Depends(require_auth)])
def post_coach_explain(body: CoachExplainBody):
    """Generate a short Spanish narrative from a cached coach report (LLM if configured).

    Rate limit: one LLM call per device per UTC calendar day. Cached narrative is
    returned on repeat requests for the same day. User notes are only sent when
    ``include_note`` is true (iOS Settings toggle).
    """
    _parse_date(body.day)
    usage_day = _dt.datetime.now(_dt.timezone.utc).date()
    with psycopg.connect(cfg.db_dsn) as conn:
        row = read.query_coach_report(conn, body.device, body.day)
        if row is None:
            raise HTTPException(
                status_code=404,
                detail="no coach report for this day; POST /v1/coach/day first",
            )
        if row.get("narrative"):
            return {"narrative": row["narrative"], "source": "cached", "day": body.day}

        prior = store.get_coach_explain_usage(conn, body.device, usage_day)
        if prior is not None and prior != body.day:
            raise HTTPException(
                status_code=429,
                detail="coach explain rate limit: one LLM narrative per UTC day",
            )

        note = None
        if body.include_note:
            plans = read.query_workout_day_plans(conn, body.device, body.day, body.day)
            if plans:
                note = plans[0].get("note")

        narrative, source = training_coach_explain.explain_report(
            row["report"],
            include_note=body.include_note,
            note=note,
        )
        store.set_coach_narrative(conn, body.device, body.day, narrative)
        if source == "llm":
            store.record_coach_explain_usage(conn, body.device, usage_day, body.day)
        conn.commit()
    return {"narrative": narrative, "source": source, "day": body.day}


# ── Backfill workouts endpoint ────────────────────────────────────────────────

class BackfillWorkouts(BaseModel):
    device: str
    # "from"/"to" are Python keywords; declare them via alias so FastAPI/Pydantic
    # deserialises {"from": "...", "to": "..."} directly without a manual remap.
    # populate_by_name=True keeps from_date/to_date working for any internal callers.
    from_date: str | None = Field(default=None, alias="from")
    to_date:   str | None = Field(default=None, alias="to")

    model_config = {"populate_by_name": True}


@app.post("/v1/backfill-workouts", dependencies=[Depends(require_auth)])
def backfill_workouts(body: BackfillWorkouts):
    """Recompute exercise sessions (with calories) over a date range by replaying
    compute_day for each date. Idempotent — safe to re-run. May be slow for large
    ranges (runs the full daily pipeline per day). Auth-gated."""
    from_str = body.from_date
    to_str = body.to_date
    if from_str is None or to_str is None:
        raise HTTPException(status_code=422, detail="'from' and 'to' are required (YYYY-MM-DD)")
    start = _parse_date(from_str)
    end = _parse_date(to_str)
    if end < start:
        raise HTTPException(status_code=422, detail="'to' must be >= 'from'")
    results = []
    with psycopg.connect(cfg.db_dsn) as conn:
        day = start
        while day <= end:
            try:
                result = daily.compute_day(conn, body.device, day)
                conn.commit()
                results.append({"date": day.isoformat(), "status": "ok",
                                "exercises": result.get("exercises", [])})
            except Exception as exc:
                conn.rollback()
                _log.exception("backfill-workouts compute_day failed for %s %s", body.device, day)
                results.append({"date": day.isoformat(), "status": "error", "detail": str(exc)})
            day += _dt.timedelta(days=1)
    return {"recomputed": len(results), "days": results}


@app.get("/v1/batches/{batch_id}/frames", dependencies=[Depends(require_auth)])
def get_batch_frames(batch_id: str):
    with psycopg.connect(cfg.db_dsn) as conn:
        row = conn.execute(
            "SELECT file_path FROM raw_batches WHERE batch_id = %s", (batch_id,)
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="batch not found")
    return read.read_batch_frames(row[0])
