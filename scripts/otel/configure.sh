
#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/configs"

ROLE="${1:-}"
VM_NAME="${2:-}"

if [[ -z "$ROLE" || -z "$VM_NAME" ]]; then
    echo "Usage: sudo bash configure.sh <role> <vm-name>"
    exit 1
fi

case "$ROLE" in
    nginx|app|db-master|db-slave|witness)
        CONFIG_FILE="${CONFIG_DIR}/${ROLE}.yaml"
        ;;
    *)
        echo "ERROR: Unknown VM role: $ROLE"
        exit 1
        ;;
esac

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration not found: $CONFIG_FILE"
    exit 1
fi

if ! systemctl is-enabled otelcol-contrib >/dev/null 2>&1; then
    systemctl enable otelcol-contrib
fi

# Create temporary configuration
TEMP_CONFIG="$(mktemp)"

trap 'rm -f "$TEMP_CONFIG"' EXIT

sed "s/__VM_NAME__/${VM_NAME}/g" \
    "$CONFIG_FILE" > "$TEMP_CONFIG"

# Validate before replacing the active configuration
otelcol-contrib validate \
    --config="$TEMP_CONFIG"

# Install configuration atomically
install -o root -g otelcol-contrib -m 0640 \
    "$TEMP_CONFIG" \
    /etc/otelcol-contrib/config.yaml

# Restart Collector
systemctl restart otelcol-contrib

sleep 3

if ! systemctl is-active --quiet otelcol-contrib; then
    echo "ERROR: Collector failed to start."

    journalctl -u otelcol-contrib -n 50 --no-pager

    exit 1
fi

echo "Configuration applied successfully."
echo "VM: ${VM_NAME}"
echo "Role: ${ROLE}"
