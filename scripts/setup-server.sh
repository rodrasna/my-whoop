#!/usr/bin/env bash
# Setup the OpenWhoop datastore + ingest server on this Mac (Docker, local-only).
# Idempotent: generates server/.env with random secrets on first run, brings the
# stack up, health-checks it, and prints the LAN line to paste into Secrets.xcconfig.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/server"
ENV_FILE="$SERVER/.env"
PORT="8770"
DATA_ROOT_DEFAULT="$HOME/whoop-data"

cd "$SERVER"

# --- 1. Docker available + daemon up -----------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found. Install Docker Desktop or Colima first." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon not responding. If you use Colima, run: colima start" >&2
  exit 1
fi

# --- 2. .env (generate secrets once; never overwrite) ------------------------
if [[ -f "$ENV_FILE" ]]; then
  echo ".env already exists — keeping current secrets."
  PORT="$(grep -E '^WHOOP_INGEST_PORT=' "$ENV_FILE" | cut -d= -f2- || true)"
  PORT="${PORT:-8770}"
else
  echo "Generating $ENV_FILE with random secrets..."
  KEY="$(openssl rand -hex 24)"
  DBPW="$(openssl rand -hex 16)"
  ( umask 077; cat > "$ENV_FILE" <<EOF
WHOOP_API_KEY=${KEY}
WHOOP_DB_NAME=whoop
WHOOP_DB_USER=whoop
WHOOP_DB_PASSWORD=${DBPW}
WHOOP_INGEST_PORT=${PORT}
DATA_ROOT=${DATA_ROOT_DEFAULT}
TZ=$(date +%Z 2>/dev/null || echo UTC)
EOF
  )
  chmod 600 "$ENV_FILE"
fi

DATA_ROOT="$(grep -E '^DATA_ROOT=' "$ENV_FILE" | cut -d= -f2-)"
mkdir -p "${DATA_ROOT}/whoop/db" "${DATA_ROOT}/whoop/raw"

# --- 3. Bring the stack up ----------------------------------------------------
echo "Building + starting whoop-db and whoop-ingest..."
docker compose up -d --build

# --- 4. Health check ----------------------------------------------------------
echo -n "Waiting for /healthz "
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 "http://localhost:${PORT}/healthz" >/dev/null 2>&1; then
    echo "OK"
    break
  fi
  echo -n "."
  sleep 1
done
if ! curl -fsS --max-time 2 "http://localhost:${PORT}/healthz" >/dev/null 2>&1; then
  echo
  echo "ERROR: server did not become healthy. Check: docker compose logs whoop-ingest" >&2
  exit 1
fi

# --- 5. Print LAN connection info --------------------------------------------
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo '<your-mac-LAN-IP>')"
echo ""
echo "Server is up:"
echo "  Dashboard:  http://localhost:${PORT}"
echo "  Health:     http://localhost:${PORT}/healthz"
echo "  Data dir:   ${DATA_ROOT}/whoop  (db + raw archive)"
echo ""
echo "On your iPhone build, set ios/OpenWhoop/Config/Secrets.xcconfig to:"
echo "  WHOOP_BASE_URL = http:/\$()/${LAN_IP}:${PORT}"
echo "  WHOOP_API_KEY  = <the WHOOP_API_KEY value in server/.env>"
echo "  WHOOP_DEVICE_ID = my-whoop"
echo ""
echo "Then: cd ios && xcodegen generate, rebuild on your iPhone."
echo "iPhone and Mac must be on the same Wi-Fi; allow port ${PORT} through the macOS firewall."
