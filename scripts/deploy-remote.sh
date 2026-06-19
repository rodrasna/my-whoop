#!/usr/bin/env bash
# Actualiza y reinicia el stack Docker en el servidor (ejecutar EN el VPS).
# Asume repo en ~/my-whoop y .env ya configurado.
#
# Usage (en VPS):
#   ./scripts/deploy-remote.sh
#   ./scripts/deploy-remote.sh --no-pull   # solo rebuild local

set -euo pipefail

NO_PULL=0
for arg in "$@"; do
  case "$arg" in
    --no-pull) NO_PULL=1 ;;
    -h|--help)
      echo "Usage: $0 [--no-pull]"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/server"
PORT="${WHOOP_INGEST_PORT:-8770}"

if [[ ! -f "$SERVER/.env" ]]; then
  echo "Missing $SERVER/.env — copy from .env.example and fill secrets." >&2
  exit 1
fi

PORT="$(grep -E '^WHOOP_INGEST_PORT=' "$SERVER/.env" | cut -d= -f2- || true)"
PORT="${PORT:-8770}"

cd "$ROOT"
if [[ "$NO_PULL" -eq 0 ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "→ git pull"
  git pull --ff-only
fi

cd "$SERVER"
echo "→ docker compose up -d --build"
docker compose up -d --build

echo -n "→ waiting for /healthz "
for _ in $(seq 1 45); do
  if curl -fsS --max-time 2 "http://localhost:${PORT}/healthz" >/dev/null 2>&1; then
    echo "OK"
    curl -fsS "http://localhost:${PORT}/healthz"
    echo
    exit 0
  fi
  echo -n "."
  sleep 2
done

echo
echo "ERROR: ingest unhealthy. Check: docker compose logs whoop-ingest" >&2
exit 1
