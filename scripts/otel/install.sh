
#!/usr/bin/env bash

set -Eeuo pipefail

OTEL_VERSION="${OTEL_VERSION:-0.165.0}"
PACKAGE_NAME="otelcol-contrib"

echo "======================================"
echo " OpenTelemetry Collector installation"
echo " Version: ${OTEL_VERSION}"
echo "======================================"

# Check operating system
if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot identify operating system."
    exit 1
fi

source /etc/os-release

if [[ "${ID}" != "ubuntu" ]]; then
    echo "ERROR: This installer supports Ubuntu only."
    exit 1
fi

# Check architecture
ARCH="$(dpkg --print-architecture)"

case "$ARCH" in
    amd64)
        PACKAGE_ARCH="amd64"
        ;;
    arm64)
        PACKAGE_ARCH="arm64"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Install dependencies
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl ca-certificates

# Download official Collector Contrib package
PACKAGE_FILE="${PACKAGE_NAME}_${OTEL_VERSION}_linux_${PACKAGE_ARCH}.deb"

DOWNLOAD_URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/${PACKAGE_FILE}"

echo "Downloading ${PACKAGE_FILE}"

curl --proto '=https' --tlsv1.2 -fL \
    "$DOWNLOAD_URL" \
    -o "/tmp/${PACKAGE_FILE}"

# Install package
dpkg -i "/tmp/${PACKAGE_FILE}"

rm -f "/tmp/${PACKAGE_FILE}"

# Verify installation
if ! command -v otelcol-contrib >/dev/null 2>&1; then
    echo "ERROR: Collector binary not found."
    exit 1
fi

if ! systemctl list-unit-files | grep -q '^otelcol-contrib.service'; then
    echo "ERROR: systemd service not found."
    exit 1
fi

# Prepare directories
install -d -o root -g root -m 0755 \
    /etc/otelcol-contrib

install -d -o otelcol-contrib -g otelcol-contrib -m 0750 \
    /var/lib/otelcol-contrib

echo "Collector version:"
otelcol-contrib --version

echo "Installation completed."
