"""DB operations for the ingest pipeline. All upserts are idempotent so re-uploaded
batches (store-and-forward retries) never duplicate rows."""
import json
import logging
import time

import psycopg

_log = logging.getLogger("uvicorn.error")

# Row-level ingest guards: one malformed row must not 500 the whole batch (the
# phone retries the same batch forever and the sync pipeline wedges). The ts
# window also catches ms-vs-seconds unit mistakes (a ms value lands in year
# ~58000) without rejecting ordinary device-clock skew.
_TS_MIN = 1577836800.0  # 2020-01-01 UTC


def _row_ok(r: dict, required: tuple[str, ...]) -> bool:
    for k in required:
        if r.get(k) is None:
            return False
    ts = r["ts"]
    if isinstance(ts, bool) or not isinstance(ts, (int, float)):
        return False
    return _TS_MIN <= float(ts) <= time.time() + 86400.0


def ensure_device(conn: psycopg.Connection, device_id: str, mac: str | None = None,
                  name: str | None = None) -> None:
    conn.execute(
        """INSERT INTO devices (device_id, mac, name) VALUES (%s, %s, %s)
           ON CONFLICT (device_id) DO UPDATE SET last_seen = now()""",
        (device_id, mac, name),
    )


def batch_exists(conn: psycopg.Connection, batch_id: str) -> bool:
    row = conn.execute("SELECT 1 FROM raw_batches WHERE batch_id = %s", (batch_id,)).fetchone()
    return row is not None


def insert_raw_batch(conn: psycopg.Connection, b: dict) -> None:
    conn.execute(
        """INSERT INTO raw_batches
           (batch_id, device_id, device_clock_ref, wall_clock_ref, start_ts, end_ts,
            packet_count, file_path, sha256, byte_size)
           VALUES (%(batch_id)s, %(device_id)s, %(device_clock_ref)s,
                   to_timestamp(%(wall_clock_ref)s), to_timestamp(%(start_ts)s),
                   to_timestamp(%(end_ts)s), %(packet_count)s, %(file_path)s,
                   %(sha256)s, %(byte_size)s)
           ON CONFLICT (batch_id) DO NOTHING""",
        b,
    )


def upsert_streams(conn: psycopg.Connection, device_id: str,
                   streams: dict) -> tuple[dict, dict]:
    """Returns (upserted_counts, skipped_counts) per stream. Malformed rows
    (missing required keys or implausible ts) are skipped, not fatal."""
    counts = {"hr": 0, "rr": 0, "events": 0, "battery": 0,
              "spo2": 0, "skin_temp": 0, "resp": 0, "gravity": 0}
    skipped = dict.fromkeys(counts, 0)
    with conn.cursor() as cur:
        for r in streams.get("hr", []):
            if not _row_ok(r, ("ts", "bpm")):
                skipped["hr"] += 1
                continue
            cur.execute(
                """INSERT INTO hr_samples (device_id, ts, bpm)
                   VALUES (%s, to_timestamp(%s), %s)
                   ON CONFLICT (device_id, ts) DO UPDATE SET bpm = EXCLUDED.bpm""",
                (device_id, r["ts"], r["bpm"]))
            counts["hr"] += 1
        for r in streams.get("rr", []):
            if not _row_ok(r, ("ts", "rr_ms")):
                skipped["rr"] += 1
                continue
            cur.execute(
                """INSERT INTO rr_intervals (device_id, ts, rr_ms)
                   VALUES (%s, to_timestamp(%s), %s)
                   ON CONFLICT (device_id, ts, rr_ms) DO NOTHING""",
                (device_id, r["ts"], r["rr_ms"]))
            counts["rr"] += 1
        for r in streams.get("events", []):
            if not _row_ok(r, ("ts", "kind")):
                skipped["events"] += 1
                continue
            cur.execute(
                """INSERT INTO events (device_id, ts, kind, payload)
                   VALUES (%s, to_timestamp(%s), %s, %s)
                   ON CONFLICT (device_id, ts, kind) DO UPDATE SET payload = EXCLUDED.payload""",
                (device_id, r["ts"], r["kind"], json.dumps(r.get("payload"))))
            counts["events"] += 1
        for r in streams.get("battery", []):
            if not _row_ok(r, ("ts",)):
                skipped["battery"] += 1
                continue
            # COALESCE: the decoded upload path omits `charging`; a re-upload of
            # the same ts must not clobber a value the raw path already stored.
            cur.execute(
                """INSERT INTO battery (device_id, ts, soc, mv, charging)
                   VALUES (%s, to_timestamp(%s), %s, %s, %s)
                   ON CONFLICT (device_id, ts) DO UPDATE SET
                     soc = COALESCE(EXCLUDED.soc, battery.soc),
                     mv = COALESCE(EXCLUDED.mv, battery.mv),
                     charging = COALESCE(EXCLUDED.charging, battery.charging)""",
                (device_id, r["ts"], r.get("soc"), r.get("mv"), r.get("charging")))
            counts["battery"] += 1
        # Type-47 V24 biometric streams (raw ADC; cloud computes human units).
        for r in streams.get("spo2", []):
            if not _row_ok(r, ("ts", "red", "ir")):
                skipped["spo2"] += 1
                continue
            cur.execute(
                """INSERT INTO spo2_samples (device_id, ts, red, ir)
                   VALUES (%s, to_timestamp(%s), %s, %s)
                   ON CONFLICT (device_id, ts) DO UPDATE SET red = EXCLUDED.red, ir = EXCLUDED.ir""",
                (device_id, r["ts"], r["red"], r["ir"]))
            counts["spo2"] += 1
        for r in streams.get("skin_temp", []):
            if not _row_ok(r, ("ts", "raw")):
                skipped["skin_temp"] += 1
                continue
            cur.execute(
                """INSERT INTO skin_temp_samples (device_id, ts, raw)
                   VALUES (%s, to_timestamp(%s), %s)
                   ON CONFLICT (device_id, ts) DO UPDATE SET raw = EXCLUDED.raw""",
                (device_id, r["ts"], r["raw"]))
            counts["skin_temp"] += 1
        for r in streams.get("resp", []):
            if not _row_ok(r, ("ts", "raw")):
                skipped["resp"] += 1
                continue
            cur.execute(
                """INSERT INTO resp_samples (device_id, ts, raw)
                   VALUES (%s, to_timestamp(%s), %s)
                   ON CONFLICT (device_id, ts) DO UPDATE SET raw = EXCLUDED.raw""",
                (device_id, r["ts"], r["raw"]))
            counts["resp"] += 1
        for r in streams.get("gravity", []):
            if not _row_ok(r, ("ts", "x", "y", "z")):
                skipped["gravity"] += 1
                continue
            cur.execute(
                """INSERT INTO gravity_samples (device_id, ts, x, y, z)
                   VALUES (%s, to_timestamp(%s), %s, %s, %s)
                   ON CONFLICT (device_id, ts) DO UPDATE SET x = EXCLUDED.x, y = EXCLUDED.y, z = EXCLUDED.z""",
                (device_id, r["ts"], r["x"], r["y"], r["z"]))
            counts["gravity"] += 1
    total_skipped = sum(skipped.values())
    if total_skipped:
        _log.warning("upsert_streams %s: skipped %d malformed rows %s", device_id,
                     total_skipped, {k: v for k, v in skipped.items() if v})
    return counts, skipped


# ── Derived daily-analysis upserts (Task 2.5) ────────────────────────────────
# Idempotent: re-running compute_day for the same (device, day) / (device, start)
# overwrites in place via ON CONFLICT DO UPDATE — never duplicates.

def upsert_daily_metrics(conn: psycopg.Connection, device_id: str, day, metrics: dict) -> None:
    """Upsert the single daily_metrics row for (device_id, day). ``day`` is a
    datetime.date; ``metrics`` is the flat dict produced by daily.compute_day."""
    conn.execute(
        """INSERT INTO daily_metrics
           (device_id, day, total_sleep_min, efficiency, deep_min, rem_min, light_min,
            disturbances, resting_hr, avg_hrv, recovery, strain, exercise_count,
            sleep_start, sleep_end, spo2_pct, skin_temp_dev_c, resp_rate_bpm,
            stress_avg, stress_peak, sleep_score, sleep_score_objective, sleep_score_breakdown,
            computed_at)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                   to_timestamp(%s), to_timestamp(%s), %s, %s, %s, %s, %s, %s, %s, %s, now())
           ON CONFLICT (device_id, day) DO UPDATE SET
             total_sleep_min = EXCLUDED.total_sleep_min,
             efficiency      = EXCLUDED.efficiency,
             deep_min        = EXCLUDED.deep_min,
             rem_min         = EXCLUDED.rem_min,
             light_min       = EXCLUDED.light_min,
             disturbances    = EXCLUDED.disturbances,
             resting_hr      = EXCLUDED.resting_hr,
             avg_hrv         = EXCLUDED.avg_hrv,
             recovery        = EXCLUDED.recovery,
             strain          = EXCLUDED.strain,
             exercise_count  = EXCLUDED.exercise_count,
             sleep_start     = EXCLUDED.sleep_start,
             sleep_end       = EXCLUDED.sleep_end,
             spo2_pct        = EXCLUDED.spo2_pct,
             skin_temp_dev_c = EXCLUDED.skin_temp_dev_c,
             resp_rate_bpm   = EXCLUDED.resp_rate_bpm,
             stress_avg      = EXCLUDED.stress_avg,
             stress_peak     = EXCLUDED.stress_peak,
             sleep_score           = EXCLUDED.sleep_score,
             sleep_score_objective = EXCLUDED.sleep_score_objective,
             sleep_score_breakdown = EXCLUDED.sleep_score_breakdown,
             computed_at     = now()""",
        (device_id, day, metrics.get("total_sleep_min"), metrics.get("efficiency"),
         metrics.get("deep_min"), metrics.get("rem_min"), metrics.get("light_min"),
         metrics.get("disturbances"), metrics.get("resting_hr"), metrics.get("avg_hrv"),
         metrics.get("recovery"), metrics.get("strain"), metrics.get("exercise_count"),
         metrics.get("sleep_start"), metrics.get("sleep_end"),
         metrics.get("spo2_pct"), metrics.get("skin_temp_dev_c"), metrics.get("resp_rate_bpm"),
         metrics.get("stress_avg"), metrics.get("stress_peak"),
         metrics.get("sleep_score"), metrics.get("sleep_score_objective"),
         json.dumps(metrics.get("sleep_score_breakdown"))
         if metrics.get("sleep_score_breakdown") is not None else None),
    )


def update_daily_sleep_scores(
    conn: psycopg.Connection,
    device_id: str,
    day,
    *,
    sleep_score: float,
    sleep_score_objective: float,
    sleep_score_breakdown: dict | None,
) -> None:
    """Patch only composite sleep score columns (e.g. after check-in upsert)."""
    conn.execute(
        """UPDATE daily_metrics
           SET sleep_score = %s,
               sleep_score_objective = %s,
               sleep_score_breakdown = %s,
               computed_at = now()
           WHERE device_id = %s AND day = %s""",
        (sleep_score, sleep_score_objective,
         json.dumps(sleep_score_breakdown) if sleep_score_breakdown is not None else None,
         device_id, day),
    )


def delete_sleep_session(conn: psycopg.Connection, device_id: str, start_ts: float) -> int:
    """Delete one sleep session by start epoch (PK). Returns rows deleted."""
    with conn.cursor() as cur:
        cur.execute(
            "DELETE FROM sleep_sessions "
            "WHERE device_id = %s AND start_ts = to_timestamp(%s)",
            (device_id, start_ts),
        )
        return cur.rowcount


def delete_sleep_sessions_for_day(conn: psycopg.Connection, device_id: str, day) -> None:
    """Delete sleep sessions whose wake (end_ts UTC date) is ``day``."""
    conn.execute(
        "DELETE FROM sleep_sessions "
        "WHERE device_id = %s AND (end_ts AT TIME ZONE 'UTC')::date = %s",
        (device_id, day))


def delete_exercise_sessions_for_day(conn: psycopg.Connection, device_id: str, day) -> None:
    """Delete exercise sessions whose start_ts falls on calendar ``day`` (UTC)."""
    conn.execute(
        "DELETE FROM exercise_sessions "
        "WHERE device_id = %s "
        "AND start_ts >= %s::date AT TIME ZONE 'UTC' "
        "AND start_ts <  (%s::date + INTERVAL '1 day') AT TIME ZONE 'UTC'",
        (device_id, day, day))


def delete_sessions_for_day(conn: psycopg.Connection, device_id: str, day) -> None:
    """Delete the existing derived session rows attributed to (device_id, day) so a
    recompute that yields FEWER sessions doesn't leave stale rows behind (which would
    desync daily_metrics.exercise_count from the actual exercise_sessions rows).

    Attribution mirrors the reads/compute:
      * sleep_sessions  — the night whose END date == ``day`` (matches query_sleep).
      * exercise_sessions — those whose start_ts is within the calendar day
        [day 00:00, day+1 00:00) UTC.

    Call inside compute_day's transaction, immediately before re-inserting the freshly
    computed set, so delete + insert commit atomically (idempotent recompute)."""
    delete_sleep_sessions_for_day(conn, device_id, day)
    delete_exercise_sessions_for_day(conn, device_id, day)


def upsert_sleep_sessions(conn: psycopg.Connection, device_id: str, sessions) -> None:
    """Upsert sleep sessions (PK device_id, start_ts). ``sessions`` is an iterable
    of dicts with start/end (epoch sec), efficiency, resting_hr, avg_hrv, stages
    (list of {start,end,stage} dicts)."""
    with conn.cursor() as cur:
        for s in sessions:
            cur.execute(
                """INSERT INTO sleep_sessions
                   (device_id, start_ts, end_ts, efficiency, resting_hr, avg_hrv, stages, kind)
                   VALUES (%s, to_timestamp(%s), to_timestamp(%s), %s, %s, %s, %s, %s)
                   ON CONFLICT (device_id, start_ts) DO UPDATE SET
                     end_ts     = EXCLUDED.end_ts,
                     efficiency = EXCLUDED.efficiency,
                     resting_hr = EXCLUDED.resting_hr,
                     avg_hrv    = EXCLUDED.avg_hrv,
                     stages     = EXCLUDED.stages,
                     kind       = EXCLUDED.kind""",
                (device_id, s["start"], s["end"], s.get("efficiency"),
                 s.get("resting_hr"), s.get("avg_hrv"), json.dumps(s.get("stages") or []),
                 s.get("kind") or "main"))


def upsert_profile(conn: psycopg.Connection, device_id: str,
                   height_cm: float | None, weight_kg: float | None,
                   age: int | None, sex: str | None) -> None:
    """Upsert the user profile row for ``device_id``. All biometric fields are
    optional (None keeps the existing value via the DO UPDATE). ``sex`` must be
    one of ``"male"``, ``"female"``, ``"nonbinary"`` or ``None``."""
    conn.execute(
        """INSERT INTO profile (device_id, height_cm, weight_kg, age, sex, updated_at)
           VALUES (%s, %s, %s, %s, %s, now())
           ON CONFLICT (device_id) DO UPDATE SET
             height_cm  = EXCLUDED.height_cm,
             weight_kg  = EXCLUDED.weight_kg,
             age        = EXCLUDED.age,
             sex        = EXCLUDED.sex,
             updated_at = now()""",
        (device_id, height_cm, weight_kg, age, sex),
    )


def upsert_sleep_check_in(conn: psycopg.Connection, device_id: str, row: dict) -> None:
    """Upsert one subjective morning check-in (PK device_id, day_key)."""
    conn.execute(
        """INSERT INTO sleep_check_ins
           (device_id, day_key, morning_feeling, onset, factors, note,
            saved_at, recovery_pct, sleep_efficiency_pct, voice_transcript, analysis)
           VALUES (%s, %s, %s, %s, %s, %s, to_timestamp(%s), %s, %s, %s, %s)
           ON CONFLICT (device_id, day_key) DO UPDATE SET
             morning_feeling      = EXCLUDED.morning_feeling,
             onset                = EXCLUDED.onset,
             factors              = EXCLUDED.factors,
             note                 = EXCLUDED.note,
             saved_at             = EXCLUDED.saved_at,
             recovery_pct         = EXCLUDED.recovery_pct,
             sleep_efficiency_pct = EXCLUDED.sleep_efficiency_pct,
             voice_transcript     = EXCLUDED.voice_transcript,
             analysis             = EXCLUDED.analysis""",
        (device_id, row["day_key"], row["morning_feeling"], row["onset"],
         json.dumps(row.get("factors") or []), row.get("note"), row["saved_at"],
         row.get("recovery_pct"), row.get("sleep_efficiency_pct"),
         row.get("voice_transcript"),
         json.dumps(row.get("analysis")) if row.get("analysis") is not None else None),
    )


def upsert_exercise_sessions(conn: psycopg.Connection, device_id: str, sessions) -> None:
    """Upsert exercise sessions (PK device_id, start_ts). ``sessions`` is an iterable
    of dicts with start/end (epoch sec), avg_hr, peak_hr, strain, kind, plus the
    per-bout intensity fields duration_s, zone_time_pct (dict), avg_hrr_pct, hrmax,
    hrmax_source, calories_kcal, calories_kj. APPROXIMATE intensity fields."""
    with conn.cursor() as cur:
        for s in sessions:
            zt = s.get("zone_time_pct")
            cur.execute(
                """INSERT INTO exercise_sessions
                   (device_id, start_ts, end_ts, avg_hr, peak_hr, strain, kind,
                    duration_s, zone_time_pct, avg_hrr_pct, hrmax, hrmax_source,
                    calories_kcal, calories_kj, motion_var, hr_peaks_per_min)
                   VALUES (%s, to_timestamp(%s), to_timestamp(%s), %s, %s, %s, %s,
                           %s, %s, %s, %s, %s, %s, %s, %s, %s)
                   ON CONFLICT (device_id, start_ts) DO UPDATE SET
                     end_ts        = EXCLUDED.end_ts,
                     avg_hr        = EXCLUDED.avg_hr,
                     peak_hr       = EXCLUDED.peak_hr,
                     strain        = EXCLUDED.strain,
                     kind          = EXCLUDED.kind,
                     duration_s    = EXCLUDED.duration_s,
                     zone_time_pct = EXCLUDED.zone_time_pct,
                     avg_hrr_pct   = EXCLUDED.avg_hrr_pct,
                     hrmax         = EXCLUDED.hrmax,
                     hrmax_source  = EXCLUDED.hrmax_source,
                     calories_kcal = EXCLUDED.calories_kcal,
                     calories_kj   = EXCLUDED.calories_kj,
                     motion_var       = EXCLUDED.motion_var,
                     hr_peaks_per_min = EXCLUDED.hr_peaks_per_min""",
                (device_id, s["start"], s["end"], s.get("avg_hr"),
                 s.get("peak_hr"), s.get("strain"), s.get("kind"),
                 (int(round(s["duration_s"])) if s.get("duration_s") is not None else None),
                 (json.dumps(zt) if zt is not None else None),
                 s.get("avg_hrr_pct"), s.get("hrmax"), s.get("hrmax_source"),
                 s.get("calories_kcal"), s.get("calories_kj"),
                 s.get("motion_var"), s.get("hr_peaks_per_min")))


def delete_stress_for_day(conn: psycopg.Connection, device_id: str, day) -> None:
    """Remove stress windows attributed to calendar ``day`` (UTC)."""
    conn.execute(
        """DELETE FROM stress_samples
           WHERE device_id = %s
           AND ts >= %s::date AT TIME ZONE 'UTC'
           AND ts <  (%s::date + INTERVAL '1 day') AT TIME ZONE 'UTC'""",
        (device_id, day, day),
    )


def upsert_stress_samples(conn: psycopg.Connection, device_id: str, samples) -> None:
    """Upsert intraday stress windows (PK device_id, ts). ``ts`` is epoch seconds."""
    with conn.cursor() as cur:
        for s in samples:
            cur.execute(
                """INSERT INTO stress_samples
                   (device_id, ts, score, rmssd_ms, hr_bpm, motion_var, quality)
                   VALUES (%s, to_timestamp(%s), %s, %s, %s, %s, %s)
                   ON CONFLICT (device_id, ts) DO UPDATE SET
                     score      = EXCLUDED.score,
                     rmssd_ms   = EXCLUDED.rmssd_ms,
                     hr_bpm     = EXCLUDED.hr_bpm,
                     motion_var = EXCLUDED.motion_var,
                     quality    = EXCLUDED.quality""",
                (device_id, s["ts"], s.get("score"), s.get("rmssd_ms"),
                 s.get("hr_bpm"), s.get("motion_var"), s.get("quality")),
            )


def upsert_workout_day_plan(conn: psycopg.Connection, device_id: str, row: dict) -> None:
    """Upsert manual day plan (PK device_id, day_key)."""
    conn.execute(
        """INSERT INTO workout_day_plans
           (device_id, day_key, primary_workout_id, activity_type, crossfit_style,
            blocks_done, note, prvn_reference_day_key, is_rest_day, saved_at)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, to_timestamp(%s))
           ON CONFLICT (device_id, day_key) DO UPDATE SET
             primary_workout_id     = EXCLUDED.primary_workout_id,
             activity_type          = EXCLUDED.activity_type,
             crossfit_style         = EXCLUDED.crossfit_style,
             blocks_done            = EXCLUDED.blocks_done,
             note                   = EXCLUDED.note,
             prvn_reference_day_key = EXCLUDED.prvn_reference_day_key,
             is_rest_day            = EXCLUDED.is_rest_day,
             saved_at               = EXCLUDED.saved_at""",
        (device_id, row["day_key"], row.get("primary_workout_id"),
         row.get("activity_type"), row.get("crossfit_style"),
         json.dumps(row.get("blocks_done") or []), row.get("note"),
         row.get("prvn_reference_day_key"), bool(row.get("is_rest_day")),
         row["saved_at"]),
    )


def delete_workout_day_plan(conn: psycopg.Connection, device_id: str, day_key: str) -> None:
    conn.execute(
        "DELETE FROM workout_day_plans WHERE device_id = %s AND day_key = %s",
        (device_id, day_key),
    )


def upsert_mobility_completion(conn: psycopg.Connection, device_id: str, row: dict) -> None:
    """Upsert one guided mobility completion (PK device_id, day_key, session_kind)."""
    conn.execute(
        """INSERT INTO mobility_completions
           (device_id, day_key, session_kind, exercise_count, completed_at)
           VALUES (%s, %s, %s, %s, to_timestamp(%s))
           ON CONFLICT (device_id, day_key, session_kind) DO UPDATE SET
             exercise_count = EXCLUDED.exercise_count,
             completed_at   = EXCLUDED.completed_at""",
        (device_id, row["day_key"], row["session_kind"], row["exercise_count"],
         row["completed_at"]),
    )


def upsert_coach_report(conn: psycopg.Connection, device_id: str, day_key: str, report: dict) -> None:
    conn.execute(
        """INSERT INTO coach_reports (device_id, day_key, report, computed_at)
           VALUES (%s, %s, %s, now())
           ON CONFLICT (device_id, day_key) DO UPDATE SET
             report      = EXCLUDED.report,
             computed_at = now()""",
        (device_id, day_key, json.dumps(report)),
    )


def delete_coach_report(conn: psycopg.Connection, device_id: str, day_key: str) -> None:
    conn.execute(
        "DELETE FROM coach_reports WHERE device_id = %s AND day_key = %s",
        (device_id, day_key),
    )


def set_coach_narrative(
    conn: psycopg.Connection, device_id: str, day_key: str, narrative: str,
) -> None:
    conn.execute(
        """UPDATE coach_reports
           SET narrative = %s, narrative_at = now()
           WHERE device_id = %s AND day_key = %s""",
        (narrative, device_id, day_key),
    )


def get_coach_explain_usage(conn: psycopg.Connection, device_id: str, usage_day) -> str | None:
    row = conn.execute(
        "SELECT day_key FROM coach_explain_usage WHERE device_id = %s AND usage_day = %s",
        (device_id, usage_day),
    ).fetchone()
    return row[0] if row else None


def record_coach_explain_usage(
    conn: psycopg.Connection, device_id: str, usage_day, day_key: str,
) -> None:
    conn.execute(
        """INSERT INTO coach_explain_usage (device_id, usage_day, day_key)
           VALUES (%s, %s, %s)
           ON CONFLICT (device_id, usage_day) DO NOTHING""",
        (device_id, usage_day, day_key),
    )
