
#!/usr/bin/env bash

set -Eeuo pipefail

echo "Stopping OpenTelemetry Collector..."

systemctl stop otelcol-contrib || true
systemctl disable otelcol-contrib || true

echo "Removing OpenTelemetry Collector package..."

apt-get remove -y otelcol-contrib

echo "Collector package removed."

echo "Configuration and data directories were preserved:"
echo "/etc/otelcol-contrib"
echo "/var/lib/otelcol-contrib"

echo "Remove these directories manually only if you no longer need them."
