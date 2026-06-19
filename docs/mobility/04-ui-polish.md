# 04 — UI polish: runner, contexto PRVN, CTA en Hoy

**Estado:** ✅ Completado (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 4

## Objetivo

Mejorar discoverabilidad y contexto sin tocar la lógica de prescripción:

1. Ver vídeo **durante** la rutina guiada (no solo en la lista).
2. Ver **qué toca hoy en PRVN** antes de empezar movilidad.
3. Tener un **acceso directo en Hoy** a la sesión sugerida.

## Qué se hizo

### 1. YouTube en el runner (`MobilitySessionRunnerView`)

- Enlace *Ver en YouTube* bajo la descripción del ejercicio activo.
- Misma URL del catálogo; abre Safari sin salir del flujo del temporizador.

### 2. Tarjeta PRVN en Movilidad (`MobilityView`)

Nueva `prvnContextCard` cuando hay programa importado:

- Tipo de día PRVN (Heavy, Engine, …).
- Bloques de entreno con icono + resumen de movimientos (`PRVNBlockSummary.oneLine`).
- Patrones detectados para la movilidad.
- Si el usuario editó el plan del día en Actividad, muestra qué bloques marcó como hechos.

### 3. CTA en Hoy (`MobilityTodayCard`)

Componente nuevo en la pestaña **Hoy** (solo día actual):

- Reutiliza `ActivityRecommendationEngine` con los mismos inputs que Actividad (recovery, strain, PRVN, bouts de hoy, `blocksDone`, completados).
- Carga workouts del día desde `MetricsRepository` + `ActivityBoutClassifier`.
- Muestra título + rationale de la recomendación y botón *Abrir rutina · {sesión}*.
- Oculta la tarjeta si esa sesión ya está completada hoy.
- Deep link vía `RootTabRouter.openMobility`.

## Archivos tocados

- `ios/OpenWhoop/Mobility/MobilitySessionRunnerView.swift`
- `ios/OpenWhoop/Mobility/MobilityTodayCard.swift` (nuevo)
- `ios/OpenWhoop/Tabs/MobilityView.swift`
- `ios/OpenWhoop/Tabs/TodayView.swift`

## Validación

```bash
cd ios
xcodegen generate
xcodebuild -scheme OpenWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Build OK. Tests de engine/builder sin regresiones.

**Manual:**

1. Hoy → tarjeta MOVILIDAD con CTA (si hay recomendación y no completada).
2. Tap → pestaña Movilidad con sesión correcta preseleccionada.
3. Movilidad → tarjeta PRVN con bloques del día.
4. Empezar rutina → link YouTube visible en cada ejercicio.

## No incluido (deferido)

- Reanudar sesión a medias / historial de rachas.
- CTA de movilidad en `postStrainWindDown` (solo caminata genérica).
- Picker de 4 sesiones en una sola fila (puede quedar apretado en SE — mejora futura de layout).

## Siguiente paso

**Ítem 5:** [Assessment onboarding + historial](05-assessment-analytics.md).
