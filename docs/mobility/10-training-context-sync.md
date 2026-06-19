# 10 — Contexto de entreno (PRVN ref, descanso, imágenes)

**Estado:** ✅ Hecho (2026-06-19)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 10

## Objetivo

Coordinar Activity ↔ Movilidad con contexto explícito del día y reflejarlo en servidor + coach.

## iOS

| Pieza | Qué hace |
|-------|----------|
| `DayTrainingContext` | PRVN efectivo, descanso, patrones, etiqueta de fuente |
| `DayWorkoutEditorView` | Elegir día PRVN de referencia, descanso, bloques, nota |
| `MobilityExerciseImageView` | Thumbnails YouTube en `Mobility/ExerciseImages/` |
| `WorkoutDayPlanStore.mergeFromServer` | Pull últimos 30 días en `refresh()` |
| `MobilityCompletionStore.mergeFromServer` | Idem completados movilidad |

## Servidor

- Columnas `prvn_reference_day_key`, `is_rest_day` en `workout_day_plans`
- Coach: `training_context` + insights `rest_day_planned`, `activity_on_rest_day`, `prvn_reference_day`

## Scripts

```bash
python3 scripts/fetch_mobility_images.py   # regenerar JPGs del catálogo
./scripts/verify-server.sh               # incluye day-plans + coach/day
```

## Deploy

`server/.dockerignore` excluye `sleep-model/`, `.venv/` y artefactos de build para deploys rápidos.
