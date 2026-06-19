# 03 — Sesión post-entreno + triggers en Actividad

**Estado:** ✅ Completado (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 3

## Objetivo

Cerrar el ciclo pre-WOD → entreno → **descompresión**: rutina guiada corta (8–12 min) tras detectar un bout de entreno, con CTA en Actividad y deep link a Movilidad.

## Qué se hizo

### 1. Nuevo tipo de sesión `postWorkout`

- `MobilitySessionKind.postWorkout` con etiqueta **Post-entreno**
- Aparece en el picker de la pestaña Movilidad
- Icono: `figure.cooldown`

### 2. Timing y builder

| Parámetro | Valor |
|-----------|--------|
| Duración objetivo | 8–12 min (6–8 si recuperación baja) |
| Estáticos guiados | 75 s |
| Dinámicos | 45 s |

`buildPostWorkout` en `MobilityRoutineBuilder`:

- Pool: ejercicios `gentle` o `staticHold` de diaria/noche
- Prioriza patrones PRVN del día + zonas de foco
- Favorece estáticos suaves (`scorePostWorkout`)
- Rellena tiempo con `fillToDuration` (incluye segunda vuelta si hace falta)

### 3. Recomendación en Actividad

Nuevo `ActivityRecommendationKind.mobilityPostWorkout` cuando:

- `trainingBoutCountToday > 0`
- Hora &lt; 20
- Post-entreno **no** completado hoy

Tarjeta: *«Enfría y descomprime»* + botón *Abrir Movilidad · Post-entreno*.

### 4. Fix colateral

El trigger de *sedentarismo* ya no salta si hay bouts de entreno detectados (`trainingBoutCountToday > 0`), aunque `activityCountToday` sea 0 (caso edge de sync).

## Archivos tocados

- `ios/OpenWhoop/Mobility/MobilityModels.swift`
- `ios/OpenWhoop/Mobility/MobilityTiming.swift`
- `ios/OpenWhoop/Mobility/MobilityRoutineBuilder.swift`
- `ios/OpenWhoop/Activity/ActivityRecommendationEngine.swift`
- `ios/OpenWhoop/Activity/ActivityRecommendationCard.swift`
- `ios/OpenWhoop/Tabs/MobilityView.swift`
- `ios/OpenWhoopTests/MobilityRoutineBuilderTests.swift`
- `ios/OpenWhoopTests/ActivityRecommendationEngineTests.swift`

## Validación

```bash
cd ios
xcodebuild -scheme OpenWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OpenWhoopTests/MobilityRoutineBuilderTests \
  -only-testing:OpenWhoopTests/ActivityRecommendationEngineTests test
```

Tests nuevos:

- `testPostWorkoutTargetsEightToTwelveMinutes`
- `testPostWorkoutAfterTrainingBout`
- `testPostWorkoutSkippedWhenAlreadyDone`

## Decisiones

- No se añadió tag `post_workout` en el JSON del catálogo: se reutilizan ejercicios gentle/static de diaria y noche.
- Post-entreno tiene prioridad sobre *push/maintain* cuando ya hay bout, pero no sobre *wind down* (≥20 h) ni *postStrainWindDown* (strain muy alto).
- `postStrainWindDown` sigue sin deep link a Movilidad (mejora futura en ítem 4).

## Siguiente paso

**Ítem 4:** [UI polish](04-ui-polish.md) — YouTube en runner, bloques PRVN visibles en tab Movilidad, CTA en Hoy.
