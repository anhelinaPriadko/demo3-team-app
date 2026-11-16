#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo "Run with sudo"; exit 1; }
systemctl disable --now otelcol-contrib 2>/dev/null || true
apt-get remove -y otelcol-contrib
echo "Package removed; config/state preserved for rollback."
