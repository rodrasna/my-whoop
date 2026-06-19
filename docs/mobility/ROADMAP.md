# Movilidad — roadmap de mejoras

Lista ordenada. Cada ítem tiene su doc en `docs/mobility/NN-<slug>.md` con proceso y validación.

| # | Ítem | Estado | Doc |
|---|------|--------|-----|
| 1 | Ampliar catálogo y cobertura por patrón PRVN | ✅ Hecho | [01-catalogo-expansion.md](01-catalogo-expansion.md) |
| 2 | PRVN bloque → patrones (menos falsos positivos, peso por tipo de bloque) | ✅ Hecho | [02-prvn-block-mapping.md](02-prvn-block-mapping.md) |
| 3 | Sesión post-entreno + triggers en Actividad | ✅ Hecho | [03-post-workout.md](03-post-workout.md) |
| 4 | UI: runner (YouTube), contexto PRVN en tab, CTA en Hoy | ✅ Hecho | [04-ui-polish.md](04-ui-polish.md) |
| 5 | Assessment onboarding + historial de completados | ✅ Hecho | [05-assessment-analytics.md](05-assessment-analytics.md) |
| 6 | Tests: timing, stores, cobertura catálogo, parser, engine | ✅ Hecho | [06-tests.md](06-tests.md) |
| 7 | Deploy servidor (ingest + PRVN cache estable) | ✅ Tooling + runbook | [07-server-deploy.md](07-server-deploy.md) |
| 8 | Hardening preservación ejercicios en ingest | ✅ Hecho | [08-exercise-preservation.md](08-exercise-preservation.md) |
| 9 | Sync day-plan + completados movilidad al servidor (coach) | ✅ Hecho | [09-server-sync-coach.md](09-server-sync-coach.md) |

## Ya entregado (antes de este roadmap)

- Sesiones guiadas 15–20 min (diaria), 10–12 pre-WOD, 12–15 noche
- `MobilityRoutineBuilder` con assessment, foco manual, patrones PRVN, segunda vuelta si falta tiempo
- Tab Movilidad, runner con temporizador, deep link desde Actividad
- `ActivityRecommendationEngine` con duraciones realistas por tipo de sesión

## Orden de ejecución

```text
Fase A (prescripción):  1 → 2 → 3
Fase B (calidad):       6 (en paralelo con 2–3)
Fase C (producto):      4 → 5
Fase D (infra):         7 → 8
Fase E (coach):         9
```
