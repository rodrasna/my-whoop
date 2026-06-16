# Task 08 — Monitor de estrés intradía

> **Estado:** Fase A en progreso (servidor + iOS lectura) · **Prioridad:** Alta · **Última actualización:** 2026-06-16  
> **Objetivo:** Sustituir el placeholder «Próximamente» en `StressMonitorCard` por un score de estrés diurno real (estilo WHOOP Stress Monitor 0–3), calculado en el **servidor** a partir de HR + RR + movimiento.

---

## 1. Resumen ejecutivo

| Qué | Detalle |
|-----|---------|
| **Problema** | La tarjeta «MONITOR DE ESTRÉS» en Hoy muestra copy honesto pero **sin datos** (`StressMonitorCard.swift`). Antes decía «calibrando» de forma engañosa. |
| **Solución** | Pipeline servidor: ventanas de RR → RMSSD → comparación con baseline 14 días → score 0–3, con **gate de movimiento** para no confundir entreno con estrés. |
| **No es** | Recuperación nocturna (eso ya usa HRV del sueño en `hrv.py` + `daily_metrics.recovery`). |
| **No borra** | Ningún dato de HR/RR; solo **añade** una serie derivada `stress_samples`. |

---

## 2. Diferencia: Recuperación vs Estrés diurno

| | **Recuperación (ya existe)** | **Estrés intradía (esta tarea)** |
|--|------------------------------|----------------------------------|
| Ventana | Sueño (SWS preferido, noche) | Día entero, ventanas cortas (2–5 min) |
| HRV | RMSSD nocturno limpio (`hrv.py`) | RMSSD intradía en reposo |
| Escala | 0–100 % (verde/amarillo/rojo) | 0–3 (WHOOP-like) |
| Uso | «¿Puedo entrenar fuerte hoy?» | «¿Cómo va mi activación ahora / a lo largo del día?» |
| Señales extra | Sueño, RHR, SpO₂, temp (4.0) | **Motion** (gravity) para restar ejercicio |

Referencias WHOOP (públicas):

- [Introducing Stress Monitor](https://www.whoop.com/us/en/thelocker/introducing-stress-monitor-a-new-way-to-monitor-manage-stress/)
- HR + HRV vs baseline 14 días; motion para separar esfuerzo físico de estrés fisiológico; escala 0–3.

Paper comparativo wearables (recovery/strain, no stress proprietary): [De Gruyter 2025](https://www.degruyterbrill.com/document/doi/10.1515/teb-2025-0001/html).

Proyectos open source útiles (algoritmos, no producto):

- [POLARstress](https://github.com/galvari/POLARstress) — RMSSD en ventanas, baseline, flags.
- [Affect (Garmin)](https://github.com/yelabb/Affect) — HR + RMSSD → arousal con calibración.

---

## 3. Inventario del código actual

### 3.1 iOS (placeholder)

| Archivo | Rol |
|---------|-----|
| `ios/OpenWhoop/Design/Components/StressMonitorCard.swift` | UI placeholder + bandas de zona + franja de sueño |
| `ios/OpenWhoop/Tabs/TodayView.swift` | `stressMonitorPlaceholder` → pasa `sleepNights`, `sleepStartTs`, `sleepEndTs` |

### 3.2 Datos ya disponibles

| Stream | Servidor (`init.sql`) | iOS (`WhoopStore` / `ServerSync`) |
|--------|----------------------|-----------------------------------|
| HR 1 Hz | `hr_samples` | Sí, pull `/v1/streams/hr` |
| RR | `rr_intervals` | Sí, pull `/v1/streams/rr` |
| Gravity / motion | `gravity_samples` | Sí, pull `/v1/streams/gravity` |
| Workouts | `exercise_sessions` + API | Sí, `/v1/workouts` |

### 3.3 Código servidor reutilizable

| Módulo | Reutilizar |
|--------|------------|
| `server/ingest/app/analysis/hrv.py` | Limpieza RR (Kubios), RMSSD, `MIN_BEATS`, gaps |
| `server/ingest/app/analysis/exercise.py` | Ventanas de entreno para **excluir** del estrés |
| `server/ingest/app/analysis/daily.py` | Hook post-`compute_day` para disparar stress |
| `server/ingest/app/main.py` | Nuevo endpoint read API |

### 3.4 Lo que NO existe

- Tabla o serie `stress_*`
- Módulo `stress.py`
- Endpoint `/v1/stress` o campo en `/v1/daily`
- Pull/cache iOS de estrés
- Gráfico real en `StressMonitorCard`

---

## 4. Decisiones de arquitectura

### 4.1 Compute en servidor (obligatorio)

Alineado con el resto de OpenWhoop: **el iPhone no calcula RMSSD intradía en producción**. Motivos:

- Reutilizar `hrv.py` y tests existentes.
- Misma curva en app y dashboard web.
- RR histórico completo tras sync (el teléfono puede no tener todo el día en local).

### 4.2 Granularidad de salida

**Recomendado:** una fila cada **5 minutos** (solo si hay suficientes RR en la ventana), más flags.

```text
stress_samples(device_id, ts, score, rmssd_ms, hr_bpm, motion_var, in_workout, quality)
```

- `score`: 0.0–3.0 (float; UI redondea o muestra 0–3 entero).
- `quality`: `good` | `sparse_rr` | `motion` | `workout` | `gap` — transparencia en UI.

### 4.3 Baseline 14 días

Pool de ventanas **en reposo** (ver §5.4) de los últimos 14 días calendario:

- `baseline_rmssd` = mediana de RMSSD válidos en reposo.
- `baseline_hr` = mediana HR en las mismas ventanas.

Si `< 4 días` con datos útiles → UI «calibrando» (honesto), no inventar score.

### 4.4 No confundir con `hr_elevation` (límite 2 h)

El límite `MAX_HR_ELEVATION_DURATION_MIN = 120` en `exercise.py` / `HRElevationDetector.swift` solo evita **crear bouts automáticos** `hr_elevation` muy largos. **No borra muestras HR.** El pipeline de estrés lee **todos** los RR/HR; no aplica ese cap.

---

## 5. Algoritmo — Fase A (heurística WHOOP-like)

### 5.1 Ventanas

- Duración ventana: **5 min** (300 s).
- Paso: **5 min** (sin solapamiento en v1; solapamiento 50% opcional en v2 para curva más suave).
- Por ventana: reunir RR con `ts` ∈ [t, t+300s).

### 5.2 Limpieza RR

Reutilizar de `hrv.py`:

1. Filtro plausibilidad 300–2000 ms.
2. `nk.signal_fixpeaks(method="kubios")` si ≥ `MIN_BEATS` (20).
3. Segmentar por gaps > 3 s; usar el segmento más largo de la ventana.

Si RR válidos < 20 → `quality=sparse_rr`, **no score** (null).

### 5.3 RMSSD

Task Force RMSSD en ms (ya implementado en `hrv.py` — extraer función pública si hace falta `rmssd_from_rr_window(rr_ms) -> float`).

### 5.4 Gate «reposo» (motion)

Por ventana, calcular `motion_var` desde `gravity_samples` (misma idea que `exercise.py`):

- Si `motion_var` > umbral **o** solapamiento > 50 % con `exercise_sessions` → `quality=workout` o `motion`, **no score** (o score atenuado en v2).

Umbral inicial: calibrar con datos reales; empezar con percentil 60 de motion en entrenos conocidos vs percentil 40 en sueño sentado.

### 5.5 HR media ventana

Media de `hr_samples` en la ventana (para componente HR del score).

### 5.6 Score 0–3

Para ventanas en reposo con RMSSD válido:

```text
z_hrv = (baseline_rmssd - rmssd) / max(baseline_rmssd * 0.15, 5)   # baja HRV → más estrés
z_hr  = (hr - baseline_hr) / max(baseline_hr * 0.10, 3)             # HR alta → más estrés
activation = 0.6 * z_hrv + 0.4 * z_hr                                 # pesos iniciales
score = clip(activation * 0.8 + 1.0, 0, 3)                          # centrado ~1 en baseline
```

- `score < 0.8` → bajo (relajado)
- `0.8 – 1.8` → medio
- `1.8 – 2.4` → alto
- `> 2.4` → pico

**Importante:** esto es v1 calibrable; documentar constantes en `stress.py` y ajustar con tu ground truth subjetivo (logs «estresado en reunión»).

### 5.7 Día sin baseline

- Mostrar gráfico solo con puntos «raw» (RMSSD) o mensaje: «Necesitas X días más de datos en reposo».
- `StressMonitorCard`: `completedNights` ya cuenta noches de sueño; añadir `restWindowsDays` del servidor.

---

## 6. Modelo de datos

### 6.1 Migración SQL (`server/db/init.sql`)

```sql
CREATE TABLE IF NOT EXISTS stress_samples (
    device_id   TEXT NOT NULL,
    ts          TIMESTAMPTZ NOT NULL,
    score       REAL,           -- 0..3, NULL si no calculable
    rmssd_ms    REAL,
    hr_bpm      SMALLINT,
    motion_var  REAL,
  quality     TEXT NOT NULL DEFAULT 'good',  -- good|sparse_rr|motion|workout|gap
    PRIMARY KEY (device_id, ts)
);
SELECT create_hypertable('stress_samples', 'ts', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS stress_samples_device_day
    ON stress_samples (device_id, ts DESC);
```

Opcional en `daily_metrics`:

```sql
ALTER TABLE daily_metrics ADD COLUMN IF NOT EXISTS stress_avg REAL;
ALTER TABLE daily_metrics ADD COLUMN IF NOT EXISTS stress_peak REAL;
```

### 6.2 Idempotencia

`compute_stress_day(device, day)`:

1. DELETE stress_samples WHERE device AND ts en día local (timezone usuario: **Europe/Madrid** por defecto; luego perfil).
2. INSERT ventanas recalculadas.

---

## 7. API

### 7.1 Lectura (Bearer, como el resto)

```http
GET /v1/stress?device=my-whoop&from=2026-06-16&to=2026-06-16&limit=500
```

Respuesta:

```json
[
  {
    "ts": "2026-06-16T09:05:00+02:00",
    "score": 1.4,
    "rmssd_ms": 42.3,
    "hr_bpm": 68,
    "quality": "good"
  }
]
```

### 7.2 Cálculo

Opción A (recomendada): integrar en pipeline existente:

```http
POST /v1/compute-daily  # ya existe — añadir paso stress al final
```

Opción B: endpoint dedicado backfill:

```http
POST /v1/compute-stress?device=my-whoop&from=2026-06-01&to=2026-06-16
```

### 7.3 Dashboard web

Añadir serie en `server/ingest/app/static/app.js` (opcional, fase 1.5).

---

## 8. iOS

### 8.1 ServerSync

- Nuevo método `fetchStress(from:to:)` → `[(ts, score, quality)]`.
- Cache en `WhoopStore` (nueva tabla `stressSample` o JSON en daily cache) — **mínimo v1:** fetch on-demand al abrir Hoy sin persistir local.

### 8.2 MetricsRepository

```swift
func stressSamples(for day: Date) async -> [StressPoint]
```

### 8.3 StressMonitorCard

Reemplazar `chartContent` placeholder por `Swift Charts` (igual que otras vistas):

- Eje X: 24 h día local.
- Eje Y: 0–3 con bandas de color (ya existen `stressHigh/Medium/Low`).
- Puntos grises cuando `quality != good`.
- Overlay sueño (ya existe `sleepBandOverlay`).
- Banner: si `calibrating` → mensaje real; si ok → «Pico hoy 2.3 a las 11:40».

### 8.4 Archivos a tocar (lista)

| Archivo | Cambio |
|---------|--------|
| `server/db/init.sql` | Tabla `stress_samples` |
| `server/ingest/app/analysis/stress.py` | **Nuevo** — algoritmo |
| `server/ingest/app/analysis/daily.py` | Llamar `compute_stress` |
| `server/ingest/app/store/*.py` | read/write stress |
| `server/ingest/app/main.py` | `GET /v1/stress`, opcional POST compute |
| `server/ingest/tests/test_stress.py` | **Nuevo** |
| `ios/OpenWhoop/Upload/ServerSync.swift` | fetch stress |
| `ios/OpenWhoop/Metrics/MetricsRepository.swift` | facade |
| `ios/OpenWhoop/Design/Components/StressMonitorCard.swift` | gráfico real |
| `ios/OpenWhoop/Tabs/TodayView.swift` | pasar `[StressPoint]` |

---

## 9. Plan de implementación por fases

### Fase A — Servidor core (MVP)

- [x] `stress.py` con ventanas + score 0–3 + motion/workout gates
- [x] Tests unitarios `test_stress.py`
- [x] SQL `stress_samples` + store/read
- [x] `GET /v1/stress`
- [x] Hook en `compute_day`
- [ ] Verificar con datos reales + `curl`

### Fase B — iOS UI

- [x] `ServerSync.fetchStress` + `StressPoint`
- [x] `StressMonitorCard` con curva (Swift Charts)
- [ ] Calibración en campo (ajustar pesos)

### Fase C — Calibración

- [ ] 1 semana usando la app; anotar momentos de estrés percibido
- [ ] Ajustar pesos `z_hrv`/`z_hr` y umbrales motion
- [ ] Documentar en `server/ingest/docs/stress-methodology.md`

### Fase D — Opcional (v2)

- [ ] Ventanas solapadas 2.5 min step
- [ ] lnRMSSD como WHOOP recovery
- [ ] Notificación «estrés alto» (iOS)
- [ ] Breathwork links (solo UI, sin claims médicos)

---

## 10. Tests

### Servidor (`test_stress.py`)

1. RR constantes → RMSSD ≈ 0 → score alto.
2. RR muy variables → RMSSD alto → score bajo.
3. Ventana con motion alto → `quality=motion`, score null.
4. Ventana dentro de workout → `quality=workout`.
5. < 20 beats → `sparse_rr`.
6. Baseline 14d con 3 días → flag calibrating.

### iOS

1. Decode JSON `/v1/stress`.
2. Snapshot/preview `StressMonitorCard` con puntos mock.

---

## 11. Criterios de aceptación

1. Tras sync + `compute-daily`, `GET /v1/stress` devuelve ≥ 10 puntos en un día típico con pulsera puesta.
2. Durante un entreno CrossFit detectado, **no** aparecen picos de estrés 2.5–3.0 por artefacto (motion gate).
3. `StressMonitorCard` muestra curva 0–3 en Hoy, no «Próximamente».
4. Con < 4 días de baseline reposo, mensaje «calibrando» sin números falsos.
5. Recovery % en anillo **no cambia** (regresión cero).

---

## 12. Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| RR disperso de día (WHOOP no siempre envía RR) | Ventanas 5 min; quality `sparse_rr`; mostrar huecos |
| Artefactos movimiento | Gate gravity + excluir workouts |
| TZ día vs UTC | Usar día local del perfil/dispositivo (mismo fix que `localDayString` en iOS) |
| Sobrecarga compute | Solo recalcular día tocado; hypertable con retention opcional 1 año |

---

## 13. Comandos útiles (desarrollo)

```bash
# Tests stress (cuando exista)
cd server/ingest && pytest tests/test_stress.py -q

# Compute día
curl -sS -X POST "http://localhost:8770/v1/compute-daily" \
  -H "Authorization: Bearer $WHOOP_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"device":"my-whoop","day":"2026-06-16"}'

# Leer estrés
curl -sS "http://localhost:8770/v1/stress?device=my-whoop&from=2026-06-16&to=2026-06-16" \
  -H "Authorization: Bearer $WHOOP_API_KEY"
```

---

## 14. Siguiente sesión — checklist rápido

1. Crear `server/ingest/app/analysis/stress.py` (esqueleto + test RR sintético).
2. Añadir tabla en `init.sql`.
3. Wire `daily.py`.
4. Endpoint + curl verde.
5. iOS gráfico.

---

## Changelog

| Fecha | Nota |
|-------|------|
| 2026-06-16 | Documento inicial — investigación WHOOP + inventario código + spec Fase A |
