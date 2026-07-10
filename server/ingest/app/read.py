"""Read-side queries + archive-frame reader for the Whoop datastore. DB + filesystem,
no HTTP. Timestamps are returned as ISO-8601 strings (psycopg gives tz-aware datetimes;
FastAPI serialises them)."""
import json
import math

import zstandard

from .analysis.units import (
    resp_rate_bpm,
    resp_rate_series_from_rr,
    skin_temp_celsius,
    skin_temp_series_from_raw,
    spo2_percent,
    spo2_percent_window,
    spo2_series_from_samples,
)

# Rolling-window radius (samples each side) for the windowed SpO2 estimator.
# A single sample is too noisy; we use a centered window so each row's `value`
# reflects the local AC/DC ratio. Falls back to the single-sample estimate when
# there are too few neighbours.
_SPO2_WINDOW_RADIUS = 8

# kind -> (table, value columns) for the decoded stream endpoints.
_STREAMS = {
    "hr": ("hr_samples", ["bpm"]),
    "rr": ("rr_intervals", ["rr_ms"]),
    "events": ("events", ["kind", "payload"]),
    "battery": ("battery", ["soc", "mv", "charging"]),
    # Type-47 V24 biometric history. spo2/skin_temp/resp values are raw ADC counts
    # (cloud computes human units); gravity is the accel-derived vector in g.
    "spo2": ("spo2_samples", ["red", "ir"]),
    "skin_temp": ("skin_temp_samples", ["raw"]),
    "resp": ("resp_samples", ["raw"]),
    "gravity": ("gravity_samples", ["x", "y", "z"]),
}

# Which kinds may be time-bucket downsampled, and how to round each avg'd value
# column for presentation. `events` is excluded entirely (text/jsonb cols can't be
# averaged). Everything listed here has only NUMERIC value columns. Round to None
# keeps the raw float (e.g. gravity, where small magnitudes matter).
#   col -> decimal places (int) | None (keep float, no rounding)
_DOWNSAMPLE = {
    "hr": {"bpm": 0},
    "rr": {"rr_ms": 0},
    "battery": {"soc": 1, "mv": 0},
    "spo2": {"red": 0, "ir": 0},
    "skin_temp": {"raw": 1},
    "resp": {"raw": 1},
    "gravity": {"x": None, "y": None, "z": None},
}


def list_devices(conn):
    rows = conn.execute(
        "SELECT device_id, mac, name, first_seen, last_seen FROM devices ORDER BY device_id"
    ).fetchall()
    cols = ["device_id", "mac", "name", "first_seen", "last_seen"]
    return [dict(zip(cols, r)) for r in rows]


def list_batches(conn, device_id, limit=100):
    rows = conn.execute(
        """SELECT batch_id::text, device_id, received_at, start_ts, end_ts, packet_count,
                  file_path, sha256, byte_size
           FROM raw_batches WHERE device_id = %s ORDER BY start_ts DESC NULLS LAST LIMIT %s""",
        (device_id, limit),
    ).fetchall()
    cols = ["batch_id", "device_id", "received_at", "start_ts", "end_ts",
            "packet_count", "file_path", "sha256", "byte_size"]
    return [dict(zip(cols, r)) for r in rows]


def query_stream(conn, kind, device_id, start, end, limit=5000, max_points=None):
    """Return time-ordered rows for ``kind`` in [start, end] (unix seconds).

    ``limit`` is a hard safety cap on the number of returned rows. ``max_points``,
    when set, enables server-side time-bucket downsampling for high-rate streams so
    the FULL range renders (bucketed to ~chart resolution) with the latest sample at
    the right edge — instead of returning only the oldest ``limit`` rows.

    Downsampling triggers only when (a) ``max_points`` is set, (b) the kind is
    downsampleable (numeric value cols — `events` is excluded), and (c) the raw row
    count in the window exceeds ``max_points``. We do a cheap COUNT(*) first to decide;
    when it's within budget we fall through to the exact (un-bucketed) path so existing
    callers and small windows see ZERO behaviour change.

    Bucket width = max(1s, ceil((end-start)/max_points)) seconds. Each NUMERIC value
    column is avg()'d over the bucket and the bucket-start ts is returned; the bucket
    grid spans the whole window so the last bucket carries the latest data. Units
    augmentation runs on the (possibly downsampled) rows exactly as before."""
    if kind not in _STREAMS:
        raise ValueError(f"unknown stream kind: {kind}")
    table, value_cols = _STREAMS[kind]

    if max_points is not None and max_points > 0 and kind in _DOWNSAMPLE:
        # One probe: row count + the ACTUAL data extent inside the window. Bucket width
        # must be derived from the real data span (epoch seconds), not the caller's
        # nominal [start,end] — the dashboard's "all" range is a giant sentinel
        # (from=0&to=2e9), and using it would collapse hours of data into one bucket.
        total, span = conn.execute(
            f"SELECT count(*), "
            "COALESCE(extract(epoch FROM max(ts)) - extract(epoch FROM min(ts)), 0) "
            f"FROM {table} "
            "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s)",
            (device_id, start, end),
        ).fetchone()
        if total > max_points:
            return _query_stream_downsampled(
                conn, kind, table, value_cols, device_id, start, end,
                max_points, limit, span)

    cols = ["ts"] + value_cols
    sql = (f"SELECT {', '.join(cols)} FROM {table} "
           f"WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s) "
           f"ORDER BY ts LIMIT %s")
    rows = conn.execute(sql, (device_id, start, end, limit)).fetchall()
    out = [dict(zip(cols, r)) for r in rows]
    return _augment_units(kind, out)


def _query_stream_downsampled(conn, kind, table, value_cols, device_id,
                              start, end, max_points, limit, span):
    """Time-bucket downsample a numeric stream. Bucket width (whole seconds) =
    max(1, ceil(span / max_points)), where ``span`` is the ACTUAL data extent
    (max(ts)-min(ts) in the window), so the buckets track real data density rather
    than a possibly-huge sentinel window. SELECTs time_bucket(...) AS ts + avg(col)
    per value column, GROUP BY the bucket, ORDER BY ts; capped at ``limit``. Value/col
    names come from the hardcoded _STREAMS/_DOWNSAMPLE maps (never user input)."""
    width = max(1, math.ceil(max(0.0, float(span)) / max_points))
    rounding = _DOWNSAMPLE[kind]
    # Average only the NUMERIC columns named in _DOWNSAMPLE (e.g. battery.charging is a
    # boolean and must never reach avg()). Non-averaged value cols are dropped from the
    # downsampled view — acceptable, and battery is fetched without max_points anyway.
    avg_cols = [c for c in value_cols if c in rounding]
    avg_exprs = ", ".join(f"avg({c}) AS {c}" for c in avg_cols)
    cols = ["ts"] + avg_cols
    sql = (
        f"SELECT time_bucket(make_interval(secs => %s), ts) AS ts, {avg_exprs} "
        f"FROM {table} "
        "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s) "
        "GROUP BY 1 ORDER BY 1 LIMIT %s"
    )
    rows = conn.execute(sql, (width, device_id, start, end, limit)).fetchall()
    out = []
    for r in rows:
        d = dict(zip(cols, r))
        for c in avg_cols:
            v = d[c]
            if v is None:
                continue
            v = float(v)
            places = rounding[c]
            d[c] = int(round(v)) if places == 0 else (v if places is None else round(v, places))
        out.append(d)
    return _augment_units(kind, out)


def _augment_units(kind, rows):
    """Add APPROXIMATE human-unit fields (`value` + `unit`) to spo2/skin_temp/resp
    rows in place, alongside the raw columns. Uses analysis.units (pure functions).
    Other kinds (hr/rr/events/battery/gravity) are returned unchanged. SpO2 uses a
    centered rolling window over the time-ordered rows (single-sample fallback)."""
    if kind == "spo2":
        reds = [float(r["red"]) for r in rows]
        irs = [float(r["ir"]) for r in rows]
        n = len(rows)
        for i, r in enumerate(rows):
            lo = max(0, i - _SPO2_WINDOW_RADIUS)
            hi = min(n, i + _SPO2_WINDOW_RADIUS + 1)
            win_red = reds[lo:hi]
            win_ir = irs[lo:hi]
            try:
                if len(win_red) >= 2:
                    val = spo2_percent_window(win_red, win_ir)
                else:
                    val = spo2_percent(reds[i], irs[i])
            except ZeroDivisionError:
                val = None
            r["value"] = round(val, 1) if val is not None else None
            r["unit"] = "%"
    elif kind == "skin_temp":
        for r in rows:
            r["value"] = round(skin_temp_celsius(r["raw"]), 1)
            r["unit"] = "°C"
    elif kind == "resp":
        for r in rows:
            r["value"] = round(resp_rate_bpm(r["raw"]), 1)
            r["unit"] = "bpm"
    return rows


def query_resp_series(conn, device_id, start, end):
    """RSA-derived respiratory-rate trend (BrPM over time) from the RR-interval
    series in [start, end] (unix seconds). Returns [{ts, value, unit}] with ts as
    unix seconds; empty when there aren't enough clean beats. The estimate is a
    pure signal-processing trend (no per-user calibration)."""
    rows = conn.execute(
        "SELECT extract(epoch FROM ts), rr_ms FROM rr_intervals "
        "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s) "
        "ORDER BY ts",
        (device_id, start, end),
    ).fetchall()
    pairs = [(float(r[0]), float(r[1])) for r in rows if r[1] is not None]
    series = resp_rate_series_from_rr(pairs)
    return [{"ts": ts, "value": brpm, "unit": "bpm"} for ts, brpm in series]


def query_temp_series(conn, device_id, start, end):
    """Nightly skin-temperature DEVIATION (Δ°C relative to the within-night median
    raw ADC) from the skin_temp_samples table in [start, end] (unix seconds).

    Returns [{ts, value, unit}] with ts as unix seconds, sorted ascending.
    The unit is "Δ°C" to make explicit that this is a relative measurement, not
    an absolute temperature.  Returns [] when there are no rows in the window.

    DESIGN NOTE: we cannot return calibrated absolute °C because the thermistor
    chain (R₀, β, divider topology) is unknown.  Deviation from the nightly median
    cancels the additive offset entirely; only the un-calibrated slope (0.02 °C/ADC)
    affects accuracy, which is adequate for trend analysis.  This mirrors how WHOOP
    presents skin temperature in its official app.
    """
    rows = conn.execute(
        "SELECT extract(epoch FROM ts), raw FROM skin_temp_samples "
        "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s) "
        "ORDER BY ts",
        (device_id, start, end),
    ).fetchall()
    pairs = [(float(r[0]), float(r[1])) for r in rows if r[1] is not None]
    series = skin_temp_series_from_raw(pairs)
    return [{"ts": ts, "value": delta, "unit": "Δ°C"} for ts, delta in series]


def query_spo2_series(conn, device_id, start, end):
    """Windowed SpO₂ TREND (%) from spo2_samples in [start, end] (unix seconds).

    Queries the raw red/ir ADC columns, builds (ts, red, ir) triples, applies the
    windowed ratio-of-ratios estimator (spo2_series_from_samples), and returns only
    samples that passed the perfusion quality gate. Windows rejected by the gate
    (motion artefact, flat signal, off-wrist) are silently discarded — no gap-fill.

    Returns [{ts, value, unit}] with ts as unix seconds and unit="%".
    Returns [] when there are no rows in the window or all windows are rejected.

    APPROXIMATION: SpO₂ is estimated from reflectance red/IR ratios using the
    TI SLAA655 textbook formula (SpO₂ = 110 − 25·R). NOT calibrated against a
    reference oximeter. Useful as a RELATIVE TREND (detecting desaturation episodes)
    only — not as a clinical absolute value.
    """
    rows = conn.execute(
        "SELECT extract(epoch FROM ts), red, ir FROM spo2_samples "
        "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s) "
        "ORDER BY ts",
        (device_id, start, end),
    ).fetchall()
    triples = [
        (float(r[0]), float(r[1]), float(r[2]))
        for r in rows
        if r[1] is not None and r[2] is not None
    ]
    series = spo2_series_from_samples(triples)
    return [{"ts": ts, "value": pct, "unit": "%"} for ts, pct in series]


def counts(conn, device_id, start, end):
    """Accurate COUNT(*) per decoded stream + raw batches for a device within a time window.
    Unlimited (unlike the row/list endpoints) so dashboard totals are exact and comparable
    to the phone's local totals. Table names come from the hardcoded _STREAMS map (no injection)."""
    out = {}
    for kind, (table, _value_cols) in _STREAMS.items():
        out[kind] = conn.execute(
            f"SELECT count(*) FROM {table} "
            "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s)",
            (device_id, start, end),
        ).fetchone()[0]
    out["batches"] = conn.execute(
        "SELECT count(*) FROM raw_batches "
        "WHERE device_id = %s AND start_ts >= to_timestamp(%s) AND start_ts <= to_timestamp(%s)",
        (device_id, start, end),
    ).fetchone()[0]
    return out


# ── Profile reads ─────────────────────────────────────────────────────────────

_PROFILE_COLS = ["device_id", "height_cm", "weight_kg", "age", "sex", "updated_at"]


def query_profile(conn, device_id: str) -> dict | None:
    """Return the profile row for ``device_id``, or ``None`` if none exists."""
    row = conn.execute(
        f"SELECT {', '.join(_PROFILE_COLS)} FROM profile WHERE device_id = %s",
        (device_id,),
    ).fetchone()
    if row is None:
        return None
    return dict(zip(_PROFILE_COLS, row))


# ── Derived daily-analysis reads (Task 2.5) ──────────────────────────────────

_DAILY_COLS = ["device_id", "day", "total_sleep_min", "efficiency", "deep_min",
               "rem_min", "light_min", "disturbances", "resting_hr", "avg_hrv",
               "recovery", "strain", "exercise_count", "sleep_start", "sleep_end",
               "spo2_pct", "skin_temp_dev_c", "resp_rate_bpm", "computed_at",
               "sleep_score", "sleep_score_objective", "sleep_score_breakdown"]


def query_daily(conn, device_id, start_date, end_date):
    """daily_metrics rows for a device over the inclusive [start_date, end_date]
    DATE range. start_date/end_date are datetime.date (or YYYY-MM-DD strings)."""
    rows = conn.execute(
        f"SELECT {', '.join(_DAILY_COLS)} FROM daily_metrics "
        "WHERE device_id = %s AND day >= %s AND day <= %s ORDER BY day",
        (device_id, start_date, end_date),
    ).fetchall()
    out = []
    for r in rows:
        row = dict(zip(_DAILY_COLS, r))
        row["sleep_score_breakdown"] = _parse_breakdown(row.get("sleep_score_breakdown"))
        out.append(row)
    return out


def _parse_breakdown(value):
    if value is None:
        return None
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        return json.loads(value)
    return value


def query_daily_row(conn, device_id, day):
    """Single daily_metrics row for (device_id, day), or None."""
    rows = query_daily(conn, device_id, day, day)
    if not rows:
        return None
    row = rows[0]
    row["sleep_score_breakdown"] = _parse_breakdown(row.get("sleep_score_breakdown"))
    return row


def query_sleep(conn, device_id, day):
    """Sleep sessions for a device whose END falls on ``day`` (the night ending
    that morning). ``day`` is a datetime.date (or YYYY-MM-DD string). Stages are
    returned parsed (JSONB → list). Timestamps are tz-aware datetimes (ISO on the wire)."""
    cols = ["device_id", "start_ts", "end_ts", "efficiency", "resting_hr", "avg_hrv", "stages", "kind"]
    rows = conn.execute(
        f"SELECT {', '.join(cols)} FROM sleep_sessions "
        "WHERE device_id = %s AND (end_ts AT TIME ZONE 'UTC')::date = %s ORDER BY start_ts",
        (device_id, day),
    ).fetchall()
    return [dict(zip(cols, r)) for r in rows]


_CHECK_IN_COLS = [
    "device_id", "day_key", "morning_feeling", "onset", "factors", "note",
    "saved_at", "recovery_pct", "sleep_efficiency_pct", "voice_transcript", "analysis",
]


def query_sleep_check_ins(conn, device_id, start_date, end_date):
    """Subjective check-ins over inclusive [start_date, end_date] day_key range."""
    rows = conn.execute(
        f"SELECT {', '.join(_CHECK_IN_COLS)} FROM sleep_check_ins "
        "WHERE device_id = %s AND day_key >= %s AND day_key <= %s ORDER BY day_key",
        (device_id, str(start_date), str(end_date)),
    ).fetchall()
    out = []
    for r in rows:
        d = dict(zip(_CHECK_IN_COLS, r))
        if isinstance(d.get("factors"), str):
            d["factors"] = json.loads(d["factors"])
        if isinstance(d.get("analysis"), str):
            d["analysis"] = json.loads(d["analysis"])
        out.append(d)
    return out


_DAY_PLAN_COLS = [
    "device_id", "day_key", "primary_workout_id", "activity_type", "crossfit_style",
    "blocks_done", "note", "prvn_reference_day_key", "is_rest_day", "saved_at",
]

_MOBILITY_COMPLETION_COLS = [
    "device_id", "day_key", "session_kind", "exercise_count", "completed_at",
]

_VALID_MOBILITY_SESSION_KINDS = frozenset({
    "daily", "preWorkout", "postWorkout", "preSleep",
})

_VALID_PROGRAM_BLOCK_KINDS = frozenset({
    "warmup", "strength", "metcon", "accessory", "other",
})


def query_workout_day_plans(conn, device_id, start_date, end_date):
    """Day plans over inclusive [start_date, end_date] day_key range."""
    rows = conn.execute(
        f"SELECT {', '.join(_DAY_PLAN_COLS)} FROM workout_day_plans "
        "WHERE device_id = %s AND day_key >= %s AND day_key <= %s ORDER BY day_key",
        (device_id, str(start_date), str(end_date)),
    ).fetchall()
    out = []
    for r in rows:
        d = dict(zip(_DAY_PLAN_COLS, r))
        if isinstance(d.get("blocks_done"), str):
            d["blocks_done"] = json.loads(d["blocks_done"])
        out.append(d)
    return out


def query_mobility_completions(conn, device_id, start_date, end_date):
    """Mobility completions over inclusive [start_date, end_date] day_key range."""
    rows = conn.execute(
        f"SELECT {', '.join(_MOBILITY_COMPLETION_COLS)} FROM mobility_completions "
        "WHERE device_id = %s AND day_key >= %s AND day_key <= %s "
        "ORDER BY day_key, session_kind",
        (device_id, str(start_date), str(end_date)),
    ).fetchall()
    return [dict(zip(_MOBILITY_COMPLETION_COLS, r)) for r in rows]


def query_coach_report(conn, device_id: str, day_key: str) -> dict | None:
    row = conn.execute(
        """SELECT report, narrative, narrative_at, computed_at FROM coach_reports
           WHERE device_id = %s AND day_key = %s""",
        (device_id, day_key),
    ).fetchone()
    if not row:
        return None
    report, narrative, narrative_at, computed_at = row
    if isinstance(report, str):
        report = json.loads(report)
    return {
        "report": report,
        "narrative": narrative,
        "narrative_at": narrative_at,
        "computed_at": computed_at,
    }


_WORKOUT_COLS = [
    "device_id", "start_ts", "end_ts", "avg_hr", "peak_hr", "strain", "kind",
    "duration_s", "zone_time_pct", "avg_hrr_pct", "hrmax", "hrmax_source",
    "calories_kcal", "calories_kj", "motion_var", "hr_peaks_per_min",
]


def count_exercise_sessions_for_day(conn, device_id, day) -> int:
    """Exercise sessions whose start_ts (UTC date) equals ``day``."""
    row = conn.execute(
        """SELECT COUNT(*) FROM exercise_sessions
           WHERE device_id = %s
           AND start_ts >= %s::date AT TIME ZONE 'UTC'
           AND start_ts <  (%s::date + INTERVAL '1 day') AT TIME ZONE 'UTC'""",
        (device_id, day, day),
    ).fetchone()
    return int(row[0]) if row else 0


def _timestamp_to_epoch(ts) -> float:
    if isinstance(ts, (int, float)):
        return float(ts)
    if hasattr(ts, "timestamp"):
        return ts.timestamp()
    raise TypeError(f"unexpected timestamp type: {type(ts)!r}")


def exercise_session_row_to_dict(row: dict) -> dict:
    """Shape a ``query_workouts`` row like ``daily._exercise_to_dict`` output."""
    zt = row.get("zone_time_pct")
    if zt is not None:
        zt = {str(k): v for k, v in zt.items()}
    return {
        "start": _timestamp_to_epoch(row["start_ts"]),
        "end": _timestamp_to_epoch(row["end_ts"]),
        "avg_hr": row.get("avg_hr"),
        "peak_hr": row.get("peak_hr"),
        "strain": row.get("strain"),
        "kind": row.get("kind"),
        "duration_s": row.get("duration_s"),
        "zone_time_pct": zt,
        "avg_hrr_pct": row.get("avg_hrr_pct"),
        "hrmax": row.get("hrmax"),
        "hrmax_source": row.get("hrmax_source"),
        "calories_kcal": row.get("calories_kcal"),
        "calories_kj": row.get("calories_kj"),
        "motion_var": row.get("motion_var"),
        "hr_peaks_per_min": row.get("hr_peaks_per_min"),
    }


def query_exercises_for_day(conn, device_id, day) -> list:
    """Persisted exercise sessions for ``day``, in ``compute_day`` response shape."""
    return [
        exercise_session_row_to_dict(r)
        for r in query_workouts(conn, device_id, day, day)
    ]


def _workout_row_to_api_dict(row: dict) -> dict:
    """Serialize a ``query_workouts*`` row for JSON (epoch seconds, string zone keys)."""
    d = dict(row)
    d["start_ts"] = _timestamp_to_epoch(d["start_ts"])
    d["end_ts"] = _timestamp_to_epoch(d["end_ts"])
    zt = d.get("zone_time_pct")
    if zt is not None:
        d["zone_time_pct"] = {str(k): v for k, v in zt.items()}
    return d


def query_workouts(conn, device_id, start_date, end_date):
    """Exercise sessions for a device whose start_ts (UTC date) is in
    [start_date, end_date] (inclusive). start_date/end_date are datetime.date
    (or YYYY-MM-DD strings). Returns all columns including calories."""
    rows = conn.execute(
        f"SELECT {', '.join(_WORKOUT_COLS)} FROM exercise_sessions "
        "WHERE device_id = %s "
        "AND (start_ts AT TIME ZONE 'UTC')::date >= %s "
        "AND (start_ts AT TIME ZONE 'UTC')::date <= %s "
        "ORDER BY start_ts",
        (device_id, start_date, end_date),
    ).fetchall()
    return [_workout_row_to_api_dict(dict(zip(_WORKOUT_COLS, r))) for r in rows]


def query_workouts_epoch(conn, device_id, start_ts: float, end_ts: float):
    """Exercise sessions with start_ts in [start_ts, end_ts) (epoch seconds).

    Used by the app for **local calendar days** (Europe/Madrid etc.) without
    splitting bouts at UTC midnight.
    """
    rows = conn.execute(
        f"SELECT {', '.join(_WORKOUT_COLS)} FROM exercise_sessions "
        "WHERE device_id = %s "
        "AND start_ts >= to_timestamp(%s) AND start_ts < to_timestamp(%s) "
        "ORDER BY start_ts",
        (device_id, start_ts, end_ts),
    ).fetchall()
    return [_workout_row_to_api_dict(dict(zip(_WORKOUT_COLS, r))) for r in rows]


_STRESS_COLS = ["device_id", "ts", "score", "rmssd_ms", "hr_bpm", "motion_var", "quality"]


def query_stress_samples(conn, device_id, start_date, end_date):
    """Stress windows with ts (UTC date) in [start_date, end_date] inclusive.

    Returns dicts with ``ts`` as epoch float (for analysis) plus numeric fields.
    """
    rows = conn.execute(
        f"""SELECT {', '.join(_STRESS_COLS)}
            FROM stress_samples
            WHERE device_id = %s
            AND (ts AT TIME ZONE 'UTC')::date >= %s
            AND (ts AT TIME ZONE 'UTC')::date <= %s
            ORDER BY ts""",
        (device_id, start_date, end_date),
    ).fetchall()
    out = []
    for r in rows:
        d = dict(zip(_STRESS_COLS, r))
        ts = d["ts"]
        if hasattr(ts, "timestamp"):
            d["ts"] = ts.timestamp()
        out.append(d)
    return out


def query_stress_day(conn, device_id, day):
    """Stress windows for a single calendar day (API: ISO ts strings)."""
    rows = conn.execute(
        f"""SELECT {', '.join(_STRESS_COLS)}
            FROM stress_samples
            WHERE device_id = %s
            AND ts >= %s::date AT TIME ZONE 'UTC'
            AND ts <  (%s::date + INTERVAL '1 day') AT TIME ZONE 'UTC'
            ORDER BY ts""",
        (device_id, day, day),
    ).fetchall()
    return [dict(zip(_STRESS_COLS, r)) for r in rows]


from whoop_protocol import parse_frame


def read_batch_frames(file_path):
    """Decompress a batch's .zst archive and parse each frame via whoop-protocol.
    Returns [{seq, hex, type_name, crc_ok, fields, parsed}] in archived order."""
    with open(file_path, "rb") as fh:
        raw = zstandard.ZstdDecompressor().decompress(fh.read())
    out = []
    for seq, line in enumerate(raw.decode().splitlines()):
        if not line:
            continue
        parsed = parse_frame(bytes.fromhex(line))
        out.append({
            "seq": seq, "hex": line, "type_name": parsed.get("type_name"),
            "crc_ok": parsed.get("crc_ok"), "fields": parsed.get("fields", []),
            "parsed": parsed.get("parsed", {}),
        })
    return out
