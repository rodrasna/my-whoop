#!/usr/bin/env bash
# Verifica que el servidor ingest responde y que PRVN/workouts están accesibles.
# Lee credenciales de ios/OpenWhoop/Config/Secrets.xcconfig (o WHOOP_SECRETS).
#
# Usage:
#   ./scripts/verify-server.sh
#   ./scripts/verify-server.sh --sync-prvn   # fuerza POST /v1/prvn/sync

set -euo pipefail

SYNC_PRVN=0
for arg in "$@"; do
  case "$arg" in
    --sync-prvn) SYNC_PRVN=1 ;;
    -h|--help)
      echo "Usage: $0 [--sync-prvn]"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${WHOOP_SECRETS:-$ROOT/ios/OpenWhoop/Config/Secrets.xcconfig}"

if [[ ! -f "$CFG" ]]; then
  echo "Secrets not found: $CFG" >&2
  exit 1
fi

read_cfg() {
  grep "^$1" "$CFG" | sed 's/.*= *//' | tr -d ' '
}

BASE=$(read_cfg WHOOP_BASE_URL | sed 's|/\$()||' | sed 's|http:/|http://|' | sed 's|https:/|https://|')
KEY=$(read_cfg WHOOP_API_KEY)
DEVICE=$(read_cfg WHOOP_DEVICE_ID)

if [[ -z "$BASE" || -z "$KEY" || -z "$DEVICE" ]]; then
  echo "WHOOP_BASE_URL, WHOOP_API_KEY and WHOOP_DEVICE_ID must be set in $CFG" >&2
  exit 1
fi

auth=(-H "Authorization: Bearer ${KEY}")

echo "→ healthz  ${BASE}/healthz"
health=$(curl -fsS --max-time 15 "${BASE}/healthz")
echo "  $health"

if [[ "$SYNC_PRVN" -eq 1 ]]; then
  echo "→ POST /v1/prvn/sync"
  curl -fsS --max-time 120 -X POST "${BASE}/v1/prvn/sync" \
    "${auth[@]}" -H "Content-Type: application/json" \
    -d "{\"device\":\"${DEVICE}\"}"
  echo
fi

echo "→ GET /v1/prvn/week?device=${DEVICE}"
prvn_code=$(curl -sS -o /tmp/whoop-prvn-week.json -w "%{http_code}" --max-time 30 \
  "${BASE}/v1/prvn/week?device=${DEVICE}" "${auth[@]}" || true)
if [[ "$prvn_code" == "200" ]]; then
  week_start=$(python3 -c "import json; print(json.load(open('/tmp/whoop-prvn-week.json')).get('week_start','?'))" 2>/dev/null || echo "?")
  echo "  OK — semana PRVN cacheada (week_start=${week_start})"
elif [[ "$prvn_code" == "404" ]]; then
  echo "  404 — sin caché PRVN. Ejecuta: $0 --sync-prvn" >&2
  exit 1
else
  echo "  HTTP ${prvn_code}" >&2
  cat /tmp/whoop-prvn-week.json 2>/dev/null || true
  exit 1
fi

TODAY=$(date +%Y-%m-%d)
echo "→ GET /v1/workouts?device=${DEVICE}&from=${TODAY}&to=${TODAY}"
workouts=$(curl -fsS --max-time 30 \
  "${BASE}/v1/workouts?device=${DEVICE}&from=${TODAY}&to=${TODAY}" "${auth[@]}")
count=$(python3 -c "import json,sys; print(len(json.load(sys.stdin)))" <<<"$workouts" 2>/dev/null || echo "?")
echo "  ${count} workout(s) hoy"

echo "→ GET /v1/day-plans?device=${DEVICE}&from=${TODAY}&to=${TODAY}"
day_plans_code=$(curl -sS -o /tmp/whoop-day-plans.json -w "%{http_code}" --max-time 15 \
  "${BASE}/v1/day-plans?device=${DEVICE}&from=${TODAY}&to=${TODAY}" "${auth[@]}" || true)
if [[ "$day_plans_code" == "200" ]]; then
  plan_count=$(python3 -c "import json; print(len(json.load(open('/tmp/whoop-day-plans.json'))))" 2>/dev/null || echo "?")
  echo "  OK — ${plan_count} day-plan(s) hoy"
else
  echo "  HTTP ${day_plans_code}" >&2
  exit 1
fi

echo "→ POST /v1/coach/day?device=${DEVICE}&day=${TODAY}"
coach_code=$(curl -sS -o /tmp/whoop-coach.json -w "%{http_code}" --max-time 30 -X POST \
  "${BASE}/v1/coach/day?device=${DEVICE}&day=${TODAY}" "${auth[@]}" || true)
if [[ "$coach_code" == "200" ]]; then
  verdict=$(python3 -c "import json; r=json.load(open('/tmp/whoop-coach.json')); print((r.get('summary') or {}).get('verdict','?'))" 2>/dev/null || echo "?")
  ctx=$(python3 -c "import json; r=json.load(open('/tmp/whoop-coach.json')); print('training_context' in r)" 2>/dev/null || echo "?")
  echo "  OK — verdict=${verdict}, training_context=${ctx}"
else
  echo "  HTTP ${coach_code}" >&2
  cat /tmp/whoop-coach.json 2>/dev/null || true
  exit 1
fi

echo ""
echo "Servidor OK para app iOS (device=${DEVICE})."
