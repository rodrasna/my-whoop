# 02 — PRVN bloque → patrones de movimiento

**Estado:** ✅ Completado (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 2

## Objetivo

Mejorar cómo inferimos **qué movilidad hace falta** a partir del programa PRVN del día: menos falsos positivos, más peso al WOD que a accesorios, y respeto a los bloques que el usuario marcó como hechos.

## Problema detectado

El parser v1 era un `contains` plano sobre keywords:

- `"press "` disparaba en palabras como *express*
- `"swing"` y `"barbell"` eran demasiado genéricos
- Todos los bloques (fuerza, WOD, accesorio) pesaban igual
- No usaba el resumen de movimientos de `PRVNBlockSummary`
- Ignoraba `WorkoutDayPlan.blocksDone` (si solo haces el WOD, la sentadilla de fuerza no debería mandar en la movilidad pre-entreno)

## Qué se hizo

### 1. Puntuación por bloque

| Tipo de bloque | Peso |
|----------------|------|
| WOD (metcon)   | ×4   |
| Fuerza         | ×3   |
| Accesorios     | ×1   |
| Calentamiento  | ignorado |

Cada keyword tiene un peso propio (frases largas > palabras sueltas). La puntuación final es `keywordWeight × blockWeight`.

### 2. Keywords con límites de palabra

- Eliminado `"press "` genérico → solo variantes concretas (`strict press`, `bench press`, `push press`, etc.)
- Plurales: `burpees`, `pull-ups`, `push-ups`, `wall balls`
- `row` con word boundary para remo/carrera
- Sin `barbell` suelto para grip

### 3. Texto analizado por bloque

Por cada `ProgramBlock` se concatena:

1. `title` (si existe)
2. `body`
3. `PRVNBlockSummary.oneLine(for:)` — nombres entre comillas / cabeceras de metcon

### 4. API nueva

```swift
PRVNMovementPatternParser.patterns(
    from: program,
    blocksDone: [.metcon]  // vacío = todos los no-warmup
)

PRVNMovementPatternParser.rankedPatterns(from:blocksDone:options:)
```

`ScanOptions`: `minimumScore` (default 2), `maxPatterns` (default 6).

### 5. Integración en la app

- **`MobilityView`**: lee `WorkoutDayPlanStore` y pasa `blocksDone` al builder
- **`WorkoutsView`**: `ActivityRecommendationContext.blocksDone` desde el plan del día
- **`ActivityRecommendationEngine`**: patrones filtrados por bloques hechos

## Archivos tocados

- `ios/OpenWhoop/Mobility/PRVNMovementPatternParser.swift` (reescrito)
- `ios/OpenWhoop/Activity/ActivityRecommendationEngine.swift`
- `ios/OpenWhoop/Tabs/MobilityView.swift`
- `ios/OpenWhoop/Tabs/WorkoutsView.swift`
- `ios/OpenWhoopTests/PRVNMovementPatternParserTests.swift` (8 tests)

## Validación

```bash
cd ios
xcodebuild -scheme OpenWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OpenWhoopTests/PRVNMovementPatternParserTests \
  -only-testing:OpenWhoopTests/MobilityRoutineBuilderTests test
```

**19 tests, 0 fallos.**

Casos cubiertos en tests:

- WOD con snatch + sentadilla + burpees
- Calentamiento con row ignorado
- `blocksDone: [.metcon]` excluye sentadilla de fuerza
- Accesorio row no cuenta si solo seleccionas metcon
- Sin falso positivo en *express / decompression*
- Español: *sentadilla trasera*
- WOD wall ball rankea por encima de push-ups de accesorio

## Decisiones

- Si `blocksDone` está **vacío**, se analizan todos los bloques (comportamiento por defecto razonable antes de editar el plan del día).
- Umbral mínimo de puntuación 2 evita ruido suelto; en texto libre (`patterns(in:)`) el umbral es 1 para tests.
- No se añadió UI nueva: el filtro usa el editor de plan del día que ya existía en Actividad.

## Siguiente paso

**Ítem 3:** [Sesión post-entreno](03-post-workout.md) — nuevo `MobilitySessionKind.postWorkout`, rutina de descompresión tras bout detectado, CTA en Actividad con deep link.
