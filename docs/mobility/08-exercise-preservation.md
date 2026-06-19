# 08 — Hardening preservación ejercicios en ingest

**Estado:** ✅ Hecho (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 8  
**Relacionado:** [07-server-deploy.md](07-server-deploy.md), `server/ingest/app/analysis/daily.py`

## Problema

Un `compute_day` / backfill matutino puede correr **antes** de que el iPhone suba el HR del entreno de la tarde. La detección devuelve **0 sesiones** y, en código antiguo, eso **borraba** workouts ya guardados → Actividad y movilidad post-WOD quedaban vacíos hasta un backfill manual.

## Regla de persistencia

En `compute_day`, al escribir `exercise_sessions`:

| Detección | Filas existentes en DB | Acción |
|-----------|------------------------|--------|
| ≥1 sesión | cualquiera | DELETE día + INSERT nuevas (puede reducir count si HR parcial) |
| 0 sesiones | 0 | DELETE día (no-op) |
| 0 sesiones | ≥1 | **No tocar** filas; `exercise_count` mantiene el count previo |

Sleep siempre se reemplaza; solo ejercicio tiene modo preserve.

## Hardening (este ítem)

### 1. Respuesta API coherente

Antes: preserve en DB pero `exercises: []` (o sin clave) en la respuesta de `compute_day` / backfill.

Ahora:

- Si el pipeline completo preserva filas → `exercises` carga desde DB (`read.query_exercises_for_day`).
- Si no hay streams del día pero sí workouts guardados → `{"status": "preserved", "exercises": [...]}` sin reescribir métricas de sueño.

### 2. Helpers en `read.py`

- `exercise_session_row_to_dict` — fila DB → dict compute
- `query_exercises_for_day` — sesiones persistidas de un día

### 3. Tests nuevos (`test_daily.py`)

| Test | Qué valida |
|------|------------|
| `test_recompute_empty_detection_preserves_existing_exercises` | DB + respuesta con count previo |
| `test_recompute_empty_detection_preserves_idempotent` | Dos recomputes vacíos seguidos |
| `test_recompute_after_preservation_updates_when_hr_returns` | HR vuelve → detección reemplaza |
| `test_preservation_is_per_device` | Device A intacto si B recomputa vacío |
| `test_compute_daily_endpoint_returns_preserved_exercises` | HTTP compute-daily + GET workouts |

Tests previos que siguen vigentes:

- `test_recompute_with_fewer_sessions_is_consistent` — menos sesiones **detectadas** sí borra stale rows
- `test_empty_day_skips_write` — día sin streams no escribe nada

## Validación

```bash
cd server/ingest
pytest tests/test_daily.py -k "preserve or fewer_sessions or empty_day" -q
```

Con Docker disponible (fixture `requires_docker`).

Tras deploy:

```bash
./scripts/verify-server.sh
# Actividad en iPhone: workouts de hoy visibles tras sync matutino
```

## Archivos tocados

| Archivo | Cambio |
|---------|--------|
| `server/ingest/app/analysis/daily.py` | preserve + `response_exercises` desde DB |
| `server/ingest/app/read.py` | `query_exercises_for_day`, conversión fila→dict |
| `server/ingest/tests/test_daily.py` | 5 tests (1 actualizado + 4 nuevos) |

## Riesgo residual

- Si la detección encuentra **1 sesión falsa** (p. ej. pico matutino) con HR real aún no subido, **sí** reemplaza las filas guardadas. Mitigación futura: umbral mínimo de duración/strain antes de wipe.
- `GET /v1/workouts` siempre leyó DB; el bug afectaba sobre todo a respuestas de backfill y clientes que confían en `compute-daily` inline.

## Siguiente paso

**Ítem 9:** sync day-plan + completados movilidad al servidor (coach).
