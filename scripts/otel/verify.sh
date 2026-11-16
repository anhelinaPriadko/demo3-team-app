
#!/usr/bin/env bash

set -Eeuo pipefail

echo "======================================"
echo " OpenTelemetry Collector verification"
echo "======================================"

FAILED=0

check() {
    local description="$1"
    shift

    echo -n "[CHECK] ${description}: "

    if "$@" >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        FAILED=1
    fi
}

check "Collector binary" \
    command -v otelcol-contrib

check "systemd service enabled" \
    systemctl is-enabled otelcol-contrib

check "systemd service active" \
    systemctl is-active otelcol-contrib

check "Configuration validation" \
    otelcol-contrib validate \
    --config=/etc/otelcol-contrib/config.yaml

echo
echo "Listening ports:"

ss -lntp | grep -E ':(4317|4318)\b' || \
    echo "No OTLP listeners found (may be expected for this role)."

echo
echo "Recent Collector logs:"

journalctl -u otelcol-contrib \
    -n 20 \
    --no-pager || true

echo

if [[ "$FAILED" -eq 0 ]]; then
    echo "All required checks passed."
else
    echo "Some checks failed."
    exit 1
fi
