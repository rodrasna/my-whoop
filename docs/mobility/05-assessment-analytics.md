# 05 — Assessment onboarding + historial de completados

**Estado:** ✅ Completado (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 5

## Objetivo

Que el usuario descubra el test de movilidad sin buscarlo en ajustes, y que vea progreso real (racha + semana) tras completar rutinas guiadas.

## Problema detectado

- El assessment solo estaba en **Ajustes → Test de movilidad** (enterrado).
- `MobilityCompletionStore` guardaba completados pero **no había UI** de historial ni racha.
- Sin tests de stores/analytics.

## Qué se hizo

### 1. Onboarding del assessment

**`MobilityAssessmentBanner`** en la pestaña Movilidad cuando:

- El test no está completo (8/8 zonas), y
- El usuario no pulsó *Más tarde* (snooze 7 días).

Acciones: *Empezar test* → sheet de assessment; *Más tarde* → oculta una semana.

**`MobilityAssessmentStore`** ampliado:

- `shouldShowOnboarding`, `snoozeOnboarding`, `completedAt` al terminar
- Progreso `ratedCount/totalAreas`

**`MobilityAssessmentView`**: barra de progreso + fecha de completado.

**`MobilityFocusSettingsView`**: muestra progreso del test en el acceso secundario.

### 2. Historial y consistencia

**`MobilityHistoryCard`** (siempre visible en Movilidad):

- Racha de días consecutivos con ≥1 sesión
- Total sesiones últimos 7 días
- Mini-calendario de 7 días (check = día con rutina)
- Link *Historial* si hay datos

**`MobilityHistoryView`** (sheet):

- Listado por día de sesiones completadas (tipo, ejercicios, hora)
- Resumen racha + semana arriba

**`MobilityCompletionAnalytics`** + métodos en store:

- `currentStreak()`, `weekSummary()`, `totalSessions()`, `recentEntries()`

### 3. Tests

Nuevo `MobilityStoresTests.swift` (6 tests):

- Umbral de zonas débiles
- Onboarding oculto al completar
- Snooze
- Racha consecutiva
- Resumen semanal
- Reemplazo misma sesión/día

## Archivos tocados

- `ios/OpenWhoop/Mobility/MobilityAssessmentStore.swift`
- `ios/OpenWhoop/Mobility/MobilityCompletionStore.swift`
- `ios/OpenWhoop/Mobility/MobilityAssessmentBanner.swift` (nuevo)
- `ios/OpenWhoop/Mobility/MobilityHistoryCard.swift` (nuevo)
- `ios/OpenWhoop/Mobility/MobilityHistoryView.swift` (nuevo)
- `ios/OpenWhoop/Mobility/MobilityAssessmentView.swift`
- `ios/OpenWhoop/Mobility/MobilityFocusSettingsView.swift`
- `ios/OpenWhoop/Tabs/MobilityView.swift`
- `ios/OpenWhoopTests/MobilityStoresTests.swift` (nuevo)

## Validación

```bash
cd ios
xcodegen generate
xcodebuild -scheme OpenWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OpenWhoopTests/MobilityStoresTests test
```

**6 tests, 0 fallos.**

## Decisiones

- Historial **solo local** (UserDefaults); sin sync servidor (ítem 9).
- Racha exige sesión **cada día consecutivo hacia atrás desde hoy**; si hoy no hay sesión, racha = 0.
- Snooze de onboarding 7 días; al completar el test el banner desaparece permanentemente.

## Siguiente paso

**Ítem 6:** [Tests](06-tests.md) — timing, parser edge cases, cobertura catálogo (parte ya cubierta en ítems 1–5).
