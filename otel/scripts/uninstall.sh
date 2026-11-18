#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

systemctl disable --now otelcol-contrib 2>/dev/null || true
systemctl disable --now nginx-prometheus-exporter 2>/dev/null || true
systemctl disable --now postgres-exporter 2>/dev/null || true

rm -f /etc/systemd/system/otelcol-contrib.service.d/10-demo3.conf
rm -f /etc/systemd/system/nginx-prometheus-exporter.service
rm -f /etc/systemd/system/postgres-exporter.service
rm -f /etc/nginx/conf.d/otel-status.conf
rm -f /usr/local/bin/nginx-prometheus-exporter
rm -f /usr/local/bin/postgres_exporter
rm -rf /etc/otel-demo3 /etc/postgres-exporter
apt-get purge -y otelcol-contrib || true
systemctl daemon-reload

echo "OpenTelemetry Collector and exporter services removed."
echo "The PostgreSQL role otel_monitor is intentionally retained; remove it manually only after confirming it is unused."
