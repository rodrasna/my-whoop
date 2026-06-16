# Roadmap tasks 08–10

Tres tareas documentadas para ejecutar **en orden**. Cada una tiene su propio markdown con contexto, decisiones, archivos y criterios de aceptación.

| Orden | ID | Tarea | Documento | Estado |
|------:|----|-------|-----------|--------|
| **1** | 08 | Monitor de estrés intradía (WHOOP-style) | [task-08-stress-monitor.md](./task-08-stress-monitor.md) | **En progreso** — Fase A/B código |
| 2 | 09 | Coach de rendimiento en entreno (reglas + LLM opcional) | [task-09-training-performance-coach.md](./task-09-training-performance-coach.md) | Pendiente (tras 08) |
| 3 | 10 | Servidor online (Hetzner CX22 + Cloudflare Tunnel) | [task-10-hetzner-hosting.md](./task-10-hetzner-hosting.md) | Pendiente (infra; puede solaparse con 08 si el servidor ya está en casa) |

## Principios comunes

- **Métricas derivadas en el servidor** (igual que recovery, strain, sueño). El iPhone renderiza y cachea.
- **Docker Compose** existente: `server/docker-compose.yml` (`whoop-db` + `whoop-ingest`).
- **Device id** habitual: `my-whoop`.
- **Tests**: pytest en `server/ingest/tests/`, XCTest en `ios/OpenWhoopTests/`.

## Cómo usar estos documentos

1. Abre el MD de la tarea activa.
2. Sigue las fases en orden; marca checkboxes al cerrar cada fase.
3. Al terminar una tarea, actualiza la columna **Estado** de esta tabla y añade una línea «Completed YYYY-MM-DD» al final del MD.

## Nota sobre paralelismo

- **08 y 10** pueden solaparse un poco (08 necesita servidor para compute; puedes desarrollar el módulo Python en local con Docker).
- **09** depende de datos de entreno estructurados (`WorkoutDayPlan`, PRVN, workouts) — ya existen en iOS; el coach server-side necesita que esos datos lleguen al servidor o se lean desde streams + etiquetas sincronizadas (ver task-09).
