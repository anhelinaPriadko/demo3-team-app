#!/usr/bin/env bash
# Dead man's switch for SigNoz. Runs from cron on demo3-signoz every 5 minutes.
# Pings healthchecks.io only when SigNoz is healthy; on a failed check it reports /fail.
# If the VM, Docker or cron die, no ping arrives and healthchecks.io sends the email itself.
set -uo pipefail

HC_URL_FILE="${HC_URL_FILE:-/opt/signoz/heartbeat.url}"   # contains https://hc-ping.com/<uuid>
DISK_LIMIT="${DISK_LIMIT:-90}"                              # % of /data
MIN_CONTAINERS="${MIN_CONTAINERS:-5}"                       # signoz, ingester, clickhouse, keeper, postgres

HC_URL="$(tr -d '[:space:]' < "$HC_URL_FILE")"
[[ -n "$HC_URL" ]] || { echo "$(date -Is) no ping URL in $HC_URL_FILE" >&2; exit 2; }

fail() {
  echo "$(date -Is) FAIL: $1"
  curl -fsS -m 10 --retry 3 --data-raw "$1" "$HC_URL/fail" >/dev/null || true
  exit 1
}

# 1. UI/API answers
curl -fsS -m 10 http://localhost:8080/api/v1/health >/dev/null \
  || fail "SigNoz API http://localhost:8080/api/v1/health is not OK"

# 2. Ingestion accepts OTLP (empty payload, nothing is stored)
code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 -X POST http://localhost:4318/v1/metrics \
  -H 'Content-Type: application/json' -d '{"resourceMetrics":[]}')"
[[ "$code" == "200" ]] || fail "OTLP HTTP ingest on :4318 returned $code"

# 3. Data disk is not full (ClickHouse stops ingesting when it is)
use="$(df --output=pcent /data | tail -n 1 | tr -dc '0-9')"
(( use < DISK_LIMIT )) || fail "/data is ${use}% full (limit ${DISK_LIMIT}%)"

# 4. Long-running containers are up
running="$(docker ps --filter name=signoz- --filter status=running -q | wc -l)"
(( running >= MIN_CONTAINERS )) || fail "only ${running} SigNoz containers running (expected ${MIN_CONTAINERS})"

curl -fsS -m 10 --retry 3 --data-raw "ok disk=${use}% containers=${running}" "$HC_URL" >/dev/null \
  || { echo "$(date -Is) could not reach healthchecks.io" >&2; exit 3; }
echo "$(date -Is) ok disk=${use}% containers=${running}"
