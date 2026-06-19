# 07 — Deploy servidor (ingest + PRVN cache)

**Estado:** ✅ Tooling y runbook listos (2026-06-18)  
**Roadmap:** [ROADMAP.md](ROADMAP.md) ítem 7  
**Runbook completo infra:** [task-10-hetzner-hosting.md](../plans/task-10-hetzner-hosting.md)

## Objetivo

Que el iPhone sincronice **sin depender del Mac**, con ingest + TimescaleDB 24/7 y caché PRVN (SugarWOD) en el servidor — requisito para Actividad, workouts y recomendaciones de movilidad basadas en PRVN real.

## Qué depende del servidor (movilidad + app)

| Función | Endpoint / componente |
|---------|------------------------|
| Workouts detectados | `GET /v1/workouts` |
| Recompute / backfill día | `POST /v1/backfill-workouts` |
| PRVN semanal (iOS) | `GET /v1/prvn/week`, `POST /v1/prvn/sync` |
| Métricas diarias | `GET /v1/daily`, recovery, strain |
| Preservar ejercicios en recompute | `server/ingest/app/analysis/daily.py` (deploy obligatorio) |
| Coach entreno (reglas) | `POST/GET /v1/coach/day` |
| Coach narrativa IA (opcional) | `POST /v1/coach/explain` — ver § OpenAI |

La pestaña **Movilidad** funciona offline (catálogo local), pero **patrones PRVN del día** y la tarjeta en **Actividad/Hoy** mejoran mucho con sync server estable.

## Qué se entregó en este ítem

### Scripts nuevos

| Script | Dónde ejecutar | Qué hace |
|--------|----------------|----------|
| [`scripts/verify-server.sh`](../../scripts/verify-server.sh) | Mac (con `Secrets.xcconfig`) | `healthz`, PRVN cache, workouts hoy |
| [`scripts/deploy-remote.sh`](../../scripts/deploy-remote.sh) | VPS | `git pull` + `docker compose up -d --build` + healthz |

```bash
# Desde el Mac — comprobar servidor configurado en Secrets.xcconfig
./scripts/verify-server.sh

# Refrescar PRVN en SugarWOD y verificar
./scripts/verify-server.sh --sync-prvn

# En el VPS — tras push al repo
./scripts/deploy-remote.sh
```

### Script existente útil

```bash
./scripts/backfill-day.sh 2026-06-18   # recompute workouts de un día
./scripts/setup-server.sh              # stack local Mac (dev)
```

## Checklist de despliegue (orden)

### A. VPS (una vez)

Seguir [task-10 §4–6](../plans/task-10-hetzner-hosting.md):

1. CX22 + Ubuntu + Docker
2. `DATA_ROOT=/srv/whoop-data`, `server/.env` con `WHOOP_API_KEY`, DB, **SugarWOD** y (opcional) **OpenAI** — ver § OpenAI
3. `docker compose up -d --build` → `curl localhost:8770/healthz`
4. `rsync` de `~/whoop-data/whoop/` desde Mac (opcional migración)
5. Cloudflare Tunnel → `https://whoop.tudominio.com`

### B. iOS

`ios/OpenWhoop/Config/Secrets.xcconfig`:

```xcconfig
WHOOP_BASE_URL = https:/$()/whoop.tudominio.com
WHOOP_API_KEY = <mismo que servidor>
WHOOP_DEVICE_ID = my-whoop
```

```bash
cd ios && xcodegen generate
```

### C. Validación post-deploy

```bash
./scripts/verify-server.sh --sync-prvn
```

Criterios:

- [ ] `healthz` → `{"status":"ok"}`
- [ ] PRVN week → 200 (no 404)
- [ ] Workouts hoy visibles en app → pestaña Actividad
- [ ] Recompute sin borrar ejercicios (código reciente en `daily.py`)
- [ ] Coach: `POST /v1/coach/day` + (opcional) `POST /v1/coach/explain` con IA activa en Ajustes

### D. Tras cada cambio en `server/`

En VPS:

```bash
cd ~/my-whoop && ./scripts/deploy-remote.sh
```

Desde Mac:

```bash
./scripts/verify-server.sh
```

## OpenAI (coach + sueño) — opcional

El ingest usa la API de OpenAI **solo en el servidor** para:

| Feature | Endpoint | Sin `OPENAI_API_KEY` |
|---------|----------|----------------------|
| Narrativa coach entreno | `POST /v1/coach/explain` | Texto plantilla en español (`source: template`) |
| Análisis voz check-in sueño | `POST /v1/sleep-check-in/analyze` | Solo reglas deterministas |

La clave **no va en el iPhone** ni en `Secrets.xcconfig`. El usuario activa la narrativa coach en **Ajustes → Coach de entreno → Narrativa con IA**; la nota del día solo se envía si marca el segundo toggle.

### Variables en `server/.env`

Añadir al `.env` del VPS (o Mac local con Docker). No commitear.

```bash
# Opcional — narrativa IA coach + refinado check-in sueño
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini   # opcional; default gpt-4o-mini
```

`docker-compose.yml` reenvía estas variables al contenedor `whoop-ingest`. Tras editar `.env`:

```bash
cd server && docker compose up -d --build whoop-ingest
```

### Comprobar coach explain (manual)

Requiere Bearer `WHOOP_API_KEY` y un informe previo (`POST /v1/coach/day`).

```bash
# 1. Generar informe del día
curl -s -X POST -H "Authorization: Bearer $WHOOP_API_KEY" \
  "https://whoop.tudominio.com/v1/coach/day?device=my-whoop&day=2026-06-18"

# 2. Pedir narrativa (template si no hay OpenAI; llm si hay clave)
curl -s -X POST -H "Authorization: Bearer $WHOOP_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"device":"my-whoop","day":"2026-06-18","include_note":false}' \
  "https://whoop.tudominio.com/v1/coach/explain"
```

Respuesta esperada: `{"narrative":"…","source":"template"|"llm"|"cached","day":"…"}`.

**Rate limit:** una llamada LLM por dispositivo y día UTC (`429` si pides otro día el mismo día calendario). Re-pedir el mismo día devuelve `cached`.

### Coste orientativo

`gpt-4o-mini` con ~200 tokens/salida y 1 explain/día → céntimos/mes. Sin clave, coste **€0** (plantilla local).

Doc completa coach: [task-09-training-performance-coach.md](../plans/task-09-training-performance-coach.md).

## Fix crítico: preservación de ejercicios

Si el servidor corre código **anterior** a junio 2026, un recompute con detección vacía **borraba** workouts ya guardados.

**Acción:** redeploy obligatorio del ingest actual. Test: `test_recompute_empty_detection_preserves_existing_exercises` en `server/ingest/tests/test_daily.py`.

```bash
cd server/ingest && pytest tests/test_daily.py -k preserves_existing -q
```

(Requiere venv con `whoop_protocol` instalado o `docker compose exec` en el contenedor.)

## Coste / ops

~€4,5/mes Hetzner CX22 + Cloudflare Tunnel gratis. Backups: ver task-10 §8.

## Pendiente (manual tuyo)

- [ ] Crear VPS y tunnel si aún no existe
- [ ] Migrar `DATA_ROOT` desde Mac
- [ ] Apuntar `Secrets.xcconfig` a URL pública
- [ ] Verificar sync desde iPhone en 4G

Este ítem **no** despliega el VPS automáticamente (credenciales y coste fuera de CI).

## Relacionado

- [08-exercise-preservation.md](08-exercise-preservation.md) — preservación workouts en recompute
- [09-server-sync-coach.md](09-server-sync-coach.md) — sync day-plan + movilidad
- [task-09-training-performance-coach.md](../plans/task-09-training-performance-coach.md) — coach Fase A/B
