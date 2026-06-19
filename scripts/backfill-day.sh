#!/usr/bin/env bash
# Recompute exercise sessions for one calendar day on the ingest server.
# Usage: ./scripts/backfill-day.sh 2026-06-18

set -euo pipefail

DAY="${1:-$(date +%Y-%m-%d)}"
CFG="${WHOOP_SECRETS:-$(dirname "$0")/../ios/OpenWhoop/Config/Secrets.xcconfig}"

if [[ ! -f "$CFG" ]]; then
  echo "Secrets not found: $CFG" >&2
  exit 1
fi

read_cfg() {
  grep "^$1" "$CFG" | sed 's/.*= *//' | tr -d ' '
}

BASE=$(read_cfg WHOOP_BASE_URL | sed 's|/\$()||' | sed 's|http:/|http://|')
KEY=$(read_cfg WHOOP_API_KEY)
DEVICE=$(read_cfg WHOOP_DEVICE_ID)

curl -sS -X POST "${BASE}/v1/backfill-workouts" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"device\":\"${DEVICE}\",\"from\":\"${DAY}\",\"to\":\"${DAY}\"}"

echo
