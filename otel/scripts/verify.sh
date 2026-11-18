#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$EUID" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ -f /etc/otel-demo3/otelcol.env ]] || { echo "Missing /etc/otel-demo3/otelcol.env" >&2; exit 1; }
source /etc/otel-demo3/otelcol.env
CONFIG=/etc/otelcol-contrib/config.yaml
[[ -f "$CONFIG" ]] || { echo "Missing Collector config" >&2; exit 1; }

otelcol-contrib validate --config="$CONFIG"
systemctl is-active --quiet otelcol-contrib || { systemctl --no-pager status otelcol-contrib; exit 1; }

OTLP_HOST="${OTEL_EXPORTER_OTLP_ENDPOINT%:*}"
OTLP_PORT="${OTEL_EXPORTER_OTLP_ENDPOINT##*:}"
timeout 5 bash -c ":</dev/tcp/${OTLP_HOST}/${OTLP_PORT}" || {
  echo "Cannot reach SigNoz OTLP endpoint ${OTEL_EXPORTER_OTLP_ENDPOINT}" >&2
  exit 1
}

check_http() {
  local label="$1" url="$2"
  if ! curl --fail --silent --show-error --max-time 5 "$url" >/dev/null; then
    echo "FAIL: $label ($url)" >&2
    return 1
  fi
  echo "OK: $label"
}

# Determine role from resource attribute / expected local services.
if systemctl is-enabled --quiet nginx-prometheus-exporter 2>/dev/null; then
  check_http "Nginx stub_status" http://127.0.0.1:8081/stub_status
  check_http "Nginx exporter" http://127.0.0.1:9113/metrics
fi
if systemctl is-enabled --quiet postgres-exporter 2>/dev/null; then
  check_http "PostgreSQL exporter" http://127.0.0.1:9187/metrics
fi

# Patroni is expected on DB nodes. If it is installed, it must expose metrics.
if systemctl list-unit-files --type=service --no-legend | grep -q '^patroni'; then
  check_http "Patroni metrics" http://127.0.0.1:8008/metrics
fi

# etcd metrics use the dedicated metrics listener, not the client port 2379.
if systemctl list-unit-files --type=service --no-legend | grep -q '^etcd'; then
  check_http "etcd metrics" http://127.0.0.1:2381/metrics
fi

echo
echo "Collector status:"
systemctl --no-pager --full status otelcol-contrib
echo
echo "Recent Collector logs:"
journalctl -u otelcol-contrib -n 40 --no-pager
echo
echo "Local checks passed. Confirm incoming metrics/logs in SigNoz UI."
