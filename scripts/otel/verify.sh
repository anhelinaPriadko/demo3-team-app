#!/usr/bin/env bash
set -Eeuo pipefail
otelcol-contrib validate --config=/etc/otelcol-contrib/config.yaml
systemctl --no-pager --full status otelcol-contrib
echo "SigNoz TCP check 10.10.0.118:4317"
timeout 3 bash -c '</dev/tcp/10.10.0.118/4317' && echo "TCP reachable" || echo "TCP unavailable: check SigNoz/VPN/SG"
journalctl -u otelcol-contrib -n 40 --no-pager
