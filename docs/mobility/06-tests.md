# 06 — Tests: cobertura del stack de movilidad

**Estado:** ✅ Completado (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 6

## Objetivo

Cerrar gaps de tests del módulo Movilidad: timing, loader, stores, parser, engine y deep links — sin regresiones en builder.

## Qué se añadió

### Nuevos archivos de test

| Archivo | Tests | Qué cubre |
|---------|-------|-----------|
| `MobilityTimingTests.swift` | 4 | Ventanas por sesión/recovery, duración guiada por modo, `durationLabel` |
| `MobilityCatalogLoaderTests.swift` | 5 | Bundle app, IDs únicos, JSON inválido, recurso ausente |
| `MobilityStoresTests.swift` | 6 | *(ítem 5)* assessment, snooze, racha, semana |

### Extensiones

| Archivo | Tests nuevos | Qué cubre |
|---------|--------------|-----------|
| `ActivityRecommendationEngineTests.swift` | +4 | `postStrainWindDown`, `fillStrainGap`, sedentario vs bout, copy movilidad |
| `PRVNMovementPatternParserTests.swift` | +2 | Umbral mínimo de score, `maxPatterns` |
| `RootTabRouterTests.swift` | +1 | Deep link `.postWorkout` |

### Infra

- Fixture `OpenWhoopTests/Fixtures/mobility_catalog_invalid.json`
- `project.yml`: resources de Fixtures en target de tests

### Ya existente (ítems 1–5)

- `MobilityRoutineBuilderTests` — 12 tests (catálogo, duración, patrones, post-entreno)
- `PRVNMovementPatternParserTests` — 10 tests total
- `ActivityRecommendationEngineTests` — 16 tests total
- `RootTabRouterTests` — 3 tests total

## Inventario total movilidad

```text
MobilityTimingTests              4
MobilityCatalogLoaderTests       5
MobilityStoresTests              6
MobilityRoutineBuilderTests     12
PRVNMovementPatternParserTests  10
ActivityRecommendationEngineTests 16
RootTabRouterTests               3
──────────────────────────────────
Total                           56 tests
```

## Validación

```bash
cd ios
xcodegen generate
xcodebuild -scheme OpenWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OpenWhoopTests/MobilityTimingTests \
  -only-testing:OpenWhoopTests/MobilityCatalogLoaderTests \
  -only-testing:OpenWhoopTests/MobilityStoresTests \
  -only-testing:OpenWhoopTests/MobilityRoutineBuilderTests \
  -only-testing:OpenWhoopTests/PRVNMovementPatternParserTests \
  -only-testing:OpenWhoopTests/ActivityRecommendationEngineTests \
  -only-testing:OpenWhoopTests/RootTabRouterTests test
```

**56 tests, 0 fallos.**

## Gaps conscientemente abiertos

- Tests de UI SwiftUI (snapshots / Maestro) — fuera de scope.
- `MobilityTodayCard` / `MobilityHistoryCard` — lógica delegada a engine + stores ya testeados.
- Loader `decodeFailed` vía `Bundle` custom — se valida decode con fixture + `missingResource` con bundle vacío.

## Siguiente paso

**Ítem 7:** [Deploy servidor](07-server-deploy.md) — ingest estable + PRVN cache (infra, no código iOS).
