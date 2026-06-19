# Task 09 — Coach de rendimiento en entreno

> **Estado:** Fases A–B hechas (2026-06-18) · Fase C ML opcional pendiente  
> **Objetivo:** Evaluar cómo fue un entreno (global y por bloques PRVN) comparando rendimiento fisiológico con tu histórico y, opcionalmente, generar narrativa con LLM en el servidor.

---

## 1. Resumen ejecutivo

| Qué | Detalle |
|-----|---------|
| **Problema** | El usuario clasifica entrenos (CrossFit, clasificatorio, bloques hechos) pero la app **no interpreta** si el pacing, la FC o el strain fueron mejores/peores que días similares. |
| **Solución en dos capas** | (1) **Motor determinista** en servidor: métricas por bloque vs baseline. (2) **LLM opcional**: texto de coaching a partir de esos números (no inventa métricas). |
| **Prerequisitos** | Workouts detectados, PRVN, `WorkoutDayPlan` (iOS local hoy) — ver §4 sincronización. |

---

## 2. Contexto de producto (ya implementado en iOS)

| Feature | Archivos |
|---------|----------|
| Clasificación entreno | `ActivityLabelStore`, `ActivityPickerView` |
| Estilo CrossFit (clasificatorio…) | `CrossFitSessionStyle`, `ActivityLabelStore.sessionStyles` |
| Estructura del día (bloques hechos) | `WorkoutDayPlanStore`, `DayWorkoutEditorView` |
| PRVN programación | `PRVNProgramStore`, SugarWOD sync |
| Detalle entreno | `WorkoutDetailView`, HR zones, strain |

**Gap:** todo lo «manual» del día vive en **UserDefaults del iPhone**. El servidor no sabe aún que hoy fue «solo WOD clasificatorio» salvo que sincronicemos ese plan.

---

## 3. Qué debería decir el coach (ejemplos)

- «WOD: 18 min en zona 4–5 vs media 12 min en tus últimos 5 clasificatorios — pacing agresivo.»
- «Fuerza: FC media similar a sesiones heavy; recuperación previa 62 % — dentro de lo esperado.»
- «Strain 14.2 vs 11.8 media en CrossFit esta semana — sesión dura.»
- «No marcaste calentamiento; la subida de FC 08:45–09:00 podría ser movilidad.»

---

## 4. Arquitectura propuesta

```text
                    ┌─────────────────────────┐
  iOS               │ WorkoutDayPlan          │
  (local)           │ activityType, blocks,   │
                    │ crossfitStyle, note     │
                    └───────────┬─────────────┘
                                │ POST /v1/day-plan (nuevo)
                                ▼
┌──────────────┐    ┌─────────────────────────┐    ┌─────────────┐
│ hr, rr,      │───▶│ training_coach.py       │───▶│ JSON report │
│ workouts,    │    │ segmentar FC por bloque │    │ + optional  │
│ prvn cache   │    │ vs baseline N días      │    │ LLM text    │
└──────────────┘    └─────────────────────────┘    └─────────────┘
```

### 4.1 Por qué reglas primero, LLM después

| Enfoque | Ventaja | Riesgo |
|---------|---------|--------|
| Solo LLM | Rápido de prototipar | Alucina números, caro, inconsistente |
| Solo reglas | Auditable, barato, offline-friendly | Texto seco |
| **Híbrido** ✓ | Números correctos + prosa | Más piezas |

---

## 5. Motor determinista (Fase A)

### 5.1 Entradas

Por `device_id` + `day` (local):

- `WorkoutDayPlan` (sincronizado desde iOS)
- `PRVNDayProgram` (cache servidor SugarWOD)
- `exercise_sessions[]` del día
- `hr_samples`, `gravity_samples` en ventana del bout principal
- `daily_metrics`: recovery, strain, resting_hr
- Histórico 30–90 días: mismos `crossfitStyle` / `activityType`

### 5.2 Segmentación temporal

1. Elegir **bout principal** (`primaryWorkoutId` del plan o mayor strain).
2. Si `blocksDone` = [metcon] solamente → analizar ventana completa como WOD.
3. Si varios bloques marcados sin tiempos explícitos → heurística:
   - Primer tercio sesión ≈ calentamiento/fuerza (si marcados)
   - Último tercio ≈ WOD/accesorios  
   (v1 burda; v2: usuario marca timestamps o integración SugarWOD blocks)

### 5.3 Features por segmento

| Feature | Comparación |
|---------|-------------|
| `duration_s` | vs media mismo estilo |
| `avg_hr`, `peak_hr` | vs media |
| `strain` | vs media |
| `% tiempo zona 2+` | vs media |
| `time_above_90%hrmax` | vs media clasificatorios |
| Recovery día anterior | contexto (no comparación) |

### 5.4 Salida JSON (`TrainingDayReport`)

```json
{
  "day": "2026-06-16",
  "style": "qualifier",
  "primary_workout_id": "my-whoop|1718534400",
  "summary": {
    "strain_vs_baseline_pct": 18.5,
    "verdict": "harder_than_usual"
  },
  "blocks": [
    {
      "kind": "metcon",
      "label": "WOD",
      "metrics": { "avg_hr": 152, "strain": 9.1 },
      "vs_baseline": { "avg_hr_pct": 6.2, "z4_minutes_pct": 22 },
      "insights": ["time_in_zone_4_above_baseline"]
    }
  ],
  "data_quality": "good"
}
```

### 5.5 Reglas de insight (ejemplos)

```python
if block.vs_baseline.z4_minutes_pct > 15:
    insights.append("time_in_zone_4_above_baseline")
if day.recovery < 0.45 and block.strain > baseline.strain * 1.1:
    insights.append("hard_session_on_low_recovery")
```

---

## 6. LLM opcional (Fase B)

### 6.1 Dónde corre

En **Hetzner** (Task 10), no en el iPhone:

- Endpoint `POST /v1/coach/explain` con el JSON de §5.4.
- Modelo: API OpenAI/Anthropic **o** Ollama pequeño en el mismo VPS (llama3.2 3B) si quieres €0 marginal.

### 6.2 Prompt template (esqueleto)

```text
Eres un coach de CrossFit. Solo usa los números del JSON.
No inventes métricas. Máximo 120 palabras. Español.
JSON: {{report}}
```

### 6.3 Privacidad

- No enviar notas personales del usuario a terceros sin toggle en Settings.
- Log mínimo; sin retención del prompt.

---

## 7. Modelo entrenado propio (Fase C — solo si hay datos)

| Requisito | Umbral orientativo |
|-----------|-------------------|
| Sesiones etiquetadas con plan + sensación (1–5) | 50–100+ |
| Features | las de §5.3 + RMSSD pre-entreno (cuando exista stress, Task 08) |

Modelo ligero (XGBoost / sklearn) para predecir «RPE subjetivo» o «cumplimiento pacing plan». **No prioritario** hasta tener histórico.

---

## 8. API y persistencia

### 8.1 Sincronizar plan del día (iOS → servidor)

```http
PUT /v1/day-plan
Authorization: Bearer …
{
  "device": "my-whoop",
  "day": "2026-06-16",
  "primary_workout_id": "…",
  "activity_type": "crossfit",
  "crossfit_style": "qualifier",
  "blocks_done": ["metcon"],
  "note": "Open 26.2 scaled"
}
```

Tabla `workout_day_plans` (JSONB o columnas).

### 8.2 Generar / leer informe

```http
POST /v1/coach/day?device=my-whoop&day=2026-06-16   # compute
GET  /v1/coach/day?device=my-whoop&day=2026-06-16   # cached
```

---

## 9. iOS UI (Fase A)

| Ubicación | Cambio |
|-----------|------|
| `WorkoutsView` → tarjeta «TU ENTRENO» | Sección «Análisis» debajo del resumen |
| `WorkoutDetailView` | Bloque insights por segmento |
| Sync | Al guardar `DayWorkoutEditorView`, `PUT /v1/day-plan` |

---

## 10. Plan de fases

### Fase A — Reglas + API (sin LLM)

- [x] Tabla `workout_day_plans` + PUT desde iOS
- [x] `training_coach.py` + tests con fixtures
- [x] GET report en Actividad
- [x] Copy en español desde plantillas (`insight_id` → frase)

### Fase B — LLM narrativo

- [x] Endpoint explain + Settings toggle
- [x] Rate limit (1/día por dispositivo UTC)

### Fase C — ML (opcional)

- [ ] Export CSV sesiones + RPE
- [ ] Entrenar baseline personalizado

---

## 11. Criterios de aceptación

1. Día con clasificatorio marcado muestra ≥ 1 insight comparativo vs histórico CrossFit.
2. Ningún insight cita métricas que no estén en el JSON fuente.
3. Sin plan del día, coach usa solo bout detectado + PRVN programado (menos preciso, indicado en UI).
4. LLM (si activo) no cambia números del report.

---

## 12. Dependencias

| Tarea | Relación |
|-------|----------|
| **08 Stress** | RMSSD pre-entreno en insights futuros |
| **10 Hetzner** | Hosting LLM / coach API 24/7 |
| Workout editor iOS | Ya hecho — falta sync servidor |

---

## 13. Archivos previstos

| Repo path | Acción |
|-----------|--------|
| `server/ingest/app/analysis/training_coach.py` | Nuevo |
| `server/ingest/app/analysis/day_plan_store.py` | Nuevo |
| `server/db/init.sql` | `workout_day_plans`, `coach_reports` |
| `server/ingest/tests/test_training_coach.py` | Nuevo |
| `ios/.../Upload/ServerSync.swift` | `putDayPlan`, `fetchCoachReport` |
| `ios/.../Activity/DayWorkoutEditorView.swift` | sync on save |

---

## Changelog

| Fecha | Nota |
|-------|------|
| 2026-06-16 | Documento inicial — arquitectura híbrida reglas + LLM |
