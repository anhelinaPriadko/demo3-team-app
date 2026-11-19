#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$EUID" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ -f /etc/otel-demo3/otelcol.env ]] || { echo "Missing /etc/otel-demo3/otelcol.env" >&2; exit 1; }
set -a; source /etc/otel-demo3/otelcol.env; set +a
CONFIG=/etc/otelcol-contrib/config.yaml
[[ -f "$CONFIG" ]] || { echo "Missing Collector config" >&2; exit 1; }

FAILED=0
ok()   { echo "OK:   $1"; }
fail() { echo "FAIL: $1" >&2; FAILED=1; }

otelcol-contrib validate --config="$CONFIG" && ok "Collector config is valid" || fail "Collector config is invalid"
systemctl is-active --quiet otelcol-contrib && ok "otelcol-contrib is active" || { systemctl --no-pager status otelcol-contrib || true; fail "otelcol-contrib is not active"; }

OTLP_HOST="${OTEL_EXPORTER_OTLP_ENDPOINT%:*}"
OTLP_PORT="${OTEL_EXPORTER_OTLP_ENDPOINT##*:}"
if timeout 5 bash -c ":</dev/tcp/${OTLP_HOST}/${OTLP_PORT}"; then
  ok "SigNoz OTLP endpoint ${OTEL_EXPORTER_OTLP_ENDPOINT} is reachable"
else
  fail "Cannot reach SigNoz OTLP endpoint ${OTEL_EXPORTER_OTLP_ENDPOINT} (VPN / security group?)"
fi

check_http() {
  local label="$1" url="$2"
  if curl --fail --silent --show-error --max-time 5 "$url" >/dev/null; then ok "$label"; else fail "$label ($url)"; fi
}

if systemctl is-enabled --quiet nginx-prometheus-exporter 2>/dev/null; then
  check_http "Nginx stub_status" http://127.0.0.1:8081/stub_status
  check_http "Nginx exporter" http://127.0.0.1:9113/metrics
  curl -s --max-time 5 http://127.0.0.1:9113/metrics | grep -q '^nginx_up 1' && ok "nginx_up = 1" || fail "nginx_up is not 1"
fi

if systemctl is-enabled --quiet postgres-exporter 2>/dev/null; then
  # The exporter needs a few seconds after a restart
  for _ in $(seq 1 10); do curl -s --max-time 3 http://127.0.0.1:9187/metrics | grep -q '^pg_up 1' && break; sleep 2; done
  curl -s --max-time 5 http://127.0.0.1:9187/metrics | grep -q '^pg_up 1' \
    && ok "PostgreSQL exporter: pg_up = 1" \
    || fail "PostgreSQL exporter: pg_up is not 1 (check pg_hba/pg_ident, journalctl -u postgres-exporter)"
fi

if systemctl list-unit-files --type=service --no-legend | grep -q '^patroni'; then
  check_http "Patroni metrics" http://127.0.0.1:8008/metrics
fi

# etcd serves /metrics on its client listener (127.0.0.1:2379)
if systemctl list-unit-files --type=service --no-legend | grep -q '^etcd'; then
  check_http "etcd metrics" http://127.0.0.1:2379/metrics
fi

# journald receiver needs a readable persistent journal
if grep -q 'journald/' "$CONFIG"; then
  [[ -d /var/log/journal ]] && ok "/var/log/journal exists" || fail "/var/log/journal is missing (set Storage=persistent in journald.conf)"
  id -nG otelcol-contrib | grep -qw systemd-journal && ok "otelcol-contrib is in systemd-journal" || fail "otelcol-contrib is not in systemd-journal"
fi

# Give the exporter time to send at least one batch, then look for export/permission errors
echo "Waiting 40s for the first exports ..."
sleep 40
ERRORS="$(journalctl -u otelcol-contrib --since '-45s' --no-pager 2>/dev/null | grep -Ei $'\terror\t|exporting failed|dropping data|permission denied|connection refused' || true)"
if [[ -n "$ERRORS" ]]; then
  echo "$ERRORS" | tail -n 20 >&2
  fail "Collector logged errors in the last 45 seconds"
else
  ok "No Collector errors in the last 45 seconds"
fi

echo
echo "Recent Collector logs:"
journalctl -u otelcol-contrib -n 20 --no-pager || true
echo

if [[ "$FAILED" -ne 0 ]]; then
  echo "Verification FAILED" >&2
  exit 1
fi
echo "All local checks passed. Confirm incoming metrics/logs in the SigNoz UI."
