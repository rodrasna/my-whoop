# 09 — Sync day-plan + completados movilidad al servidor

**Estado:** ✅ Hecho (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 9  
**Coach futuro:** [task-09-training-performance-coach.md](../plans/task-09-training-performance-coach.md)

## Objetivo

Subir al ingest los datos que hoy viven solo en UserDefaults del iPhone:

- **`WorkoutDayPlan`** — bout principal, tipo, estilo CrossFit, bloques hechos, nota
- **`MobilityCompletionEntry`** — sesión guiada completada (día + tipo + ejercicios)

Requisito para el coach server-side (Fase A de task-09) sin depender del Mac.

## API

| Método | Ruta | Uso |
|--------|------|-----|
| PUT | `/v1/day-plan` | Upsert plan del día |
| DELETE | `/v1/day-plan?device=&day=` | Usuario borra el plan |
| GET | `/v1/day-plans?device=&from=&to=` | Lectura (coach / multi-device) |
| POST | `/v1/mobility-completion` | Upsert completado |
| GET | `/v1/mobility-completions?device=&from=&to=` | Lectura |

Auth: Bearer (`WHOOP_API_KEY`), igual que el resto de `/v1/*`.

### Ejemplo day-plan

```json
{
  "device": "my-whoop",
  "day": "2026-06-16",
  "primary_workout_id": "my-whoop|1718534400",
  "activity_type": "crossfit",
  "crossfit_style": "qualifier",
  "blocks_done": ["metcon"],
  "note": "Open 26.2 scaled",
  "saved_at": 1718538000
}
```

### Ejemplo mobility

```json
{
  "device": "my-whoop",
  "day_key": "2026-06-16",
  "session_kind": "preWorkout",
  "exercise_count": 8,
  "completed_at": 1718541600
}
```

`session_kind`: `daily` | `preWorkout` | `postWorkout` | `preSleep` (rawValue iOS).

## Persistencia (TimescaleDB)

Tablas en `server/db/init.sql`:

- `workout_day_plans` — PK `(device_id, day_key)`
- `mobility_completions` — PK `(device_id, day_key, session_kind)`

Bootstrap idempotente vía `docker compose` (mismo patrón que `sleep_check_ins`).

## iOS — cuándo sincroniza

| Acción usuario | Código | Sync |
|----------------|--------|------|
| Guardar editor de entreno | `DayWorkoutEditorView.save()` | `metrics.pushDayPlan` |
| Borrar plan (campos vacíos) | mismo | `deleteDayPlan` |
| Terminar rutina movilidad | `MobilitySessionRunnerView.goNext()` | `metrics.pushMobilityCompletion` |

Best-effort: fallo de red no bloquea la UI; datos locales siguen en UserDefaults.

## Archivos

| Capa | Archivos |
|------|----------|
| DB | `server/db/init.sql` |
| Store/read | `server/ingest/app/store.py`, `read.py` |
| HTTP | `server/ingest/app/main.py` |
| Tests servidor | `server/ingest/tests/test_coach_sync.py` |
| Sync iOS | `ServerSync.swift`, `MetricsRepository.swift` |
| UI hooks | `DayWorkoutEditorView.swift`, `MobilitySessionRunnerView.swift` |
| Tests iOS | `ServerSyncTests.swift` (+3 tests) |

## Validación

```bash
# Servidor (Docker)
cd server/ingest
pytest tests/test_coach_sync.py -q

# iOS
cd ios && xcodegen generate
xcodebuild -scheme OpenWhoop -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OpenWhoopTests/ServerSyncTests test
```

Manual tras deploy:

1. Editar entreno en Actividad → `GET /v1/day-plans` muestra el día
2. Completar rutina movilidad → `GET /v1/mobility-completions` muestra la sesión

## Fuera de alcance (siguiente)

- Pull server → iOS (merge multi-device) — no necesario para coach unidireccional
- `training_coach.py` + informes — task-09 Fase A
- GET en `verify-server.sh` — opcional

## Roadmap movilidad

Con el ítem 9, la **Fase E (coach)** del roadmap de movilidad queda cerrada en cuanto a **datos en servidor**. El informe del coach es trabajo de task-09.
