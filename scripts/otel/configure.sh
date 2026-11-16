#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo "Run with sudo"; exit 1; }
ROLE="${1:-}"; VM="${2:-}"; IP="${3:-}"
[[ -n "$ROLE" && -n "$VM" && -n "$IP" ]] || { echo "Usage: sudo $0 {nginx|app|db-master|db-slave|witness} VM_NAME PRIVATE_IP"; exit 2; }
case "$ROLE" in nginx|app|db-master|db-slave|witness) ;; *) echo "Unknown role"; exit 2;; esac
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$DIR/configs/$ROLE.yaml"
command -v otelcol-contrib >/dev/null || { echo "Run scripts/install.sh first"; exit 1; }
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
sed -e "s/__VM_NAME__/${VM}/g" -e "s/__VM_PRIVATE_IP__/${IP}/g" "$SRC" > "$TMP"
otelcol-contrib validate --config="$TMP"
install -o root -g root -m 0640 "$TMP" /etc/otelcol-contrib/config.yaml
systemctl restart otelcol-contrib
sleep 2
systemctl is-active --quiet otelcol-contrib || { journalctl -u otelcol-contrib -n 80 --no-pager; exit 1; }
echo "Configured $VM ($ROLE)"
