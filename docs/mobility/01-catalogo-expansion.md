# 01 — Ampliar catálogo y cobertura por patrón PRVN

**Estado:** ✅ Completado (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 1

## Objetivo

Pasar de un catálogo mínimo (~14 ejercicios) a uno usable para rutinas de 15–20 min **sin repetir tanto**, con cobertura equilibrada de los 7 patrones de movimiento PRVN (sentadilla, bisagra, overhead, tirón, empuje, locomoción, agarre).

## Problema detectado

- `fillToDuration` tenía que hacer **segunda vuelta** de los mismos ejercicios porque el pool era pequeño.
- **Push** y **grip** casi no tenían drills propios; las rutinas pre-WOD para días de dominadas o farmer carry eran genéricas.
- El test solo exigía `>= 12` ejercicios, sin matriz de cobertura.

## Qué se hizo

### 12 ejercicios nuevos en `mobility_catalog.json`

| ID | Nombre | Patrones nuevos / reforzados |
|----|--------|------------------------------|
| `doorway-pec-stretch` | Pectoral en marco | push, overhead |
| `wall-slide` | Deslizamiento en pared | push, overhead, pull |
| `lat-wall-stretch` | Dorsal en pared | pull, overhead |
| `forearm-flexor-stretch` | Flexores antebrazo | grip, pull, push |
| `forearm-extensor-stretch` | Extensores antebrazo | grip, pull |
| `calf-wall-stretch` | Gemelo en pared | locomotion, squat |
| `cossack-squat` | Sentadilla cosaca | squat, locomotion |
| `hip-circles` | Círculos de cadera | locomotion, hinge, squat |
| `standing-quad-stretch` | Cuádriceps de pie | locomotion |
| `overhead-band-opener` | Apertura overhead banda | overhead, push, pull |
| `prone-press-up` | Cobra / press-up prono | push |
| `jefferson-curl-prep` | Flexión Jefferson | hinge |
| `scapular-push-up` | Flexión escapular | push, pull |
| `frog-stretch` | Estiramiento rana | squat, hinge |

**Total catálogo:** 26 ejercicios (14 originales + 12 nuevos).

### Criterios de diseño

- Reutilizar `MobilityPose` existentes (sin nuevos monigotes por ahora).
- Mezcla de `staticHold`, `dynamic` y `activation` según el tipo de sesión.
- Textos y nombres en **español**, descripciones accionables (cómo hacerlo, no solo qué zona).
- `session_kinds` coherentes: pre-entreno para activadores; noche solo `gentle`.

### Tests

En `MobilityRoutineBuilderTests.swift`:

- `testCatalogDecodeWithMovementTags`: umbral `>= 25` ejercicios.
- **Nuevo** `testCatalogCoversAllMovementPatternsForPreWorkout`: cada patrón tiene **≥ 2** ejercicios elegibles en pre-entreno.

## Archivos tocados

- `ios/OpenWhoop/Mobility/mobility_catalog.json`
- `ios/OpenWhoopTests/MobilityRoutineBuilderTests.swift`
- `docs/mobility/ROADMAP.md` (este ítem marcado hecho)
- `docs/mobility/01-catalogo-expansion.md` (este doc)

## Validación

```bash
cd ios
xcodebuild -scheme OpenWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OpenWhoopTests/MobilityRoutineBuilderTests test
```

Resultado: **11 tests, 0 fallos**.

## Decisiones / no hecho (a propósito)

- No se añadieron poses nuevas en `MobilityStickFigureView` — el monigote reutiliza posturas cercanas.
- URLs de YouTube son referencias genéricas de movilidad; no se validó cada vídeo en detalle.
- El catálogo sigue siendo **local** (JSON en bundle); sin sync servidor.

## Siguiente paso

**Ítem 2:** [PRVN bloque → patrones](02-prvn-block-mapping.md) — parser con menos falsos positivos, peso por tipo de bloque (metcon > fuerza > accesorio), y opcionalmente bloques marcados como hechos en `WorkoutDayPlan`.
