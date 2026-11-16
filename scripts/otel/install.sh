#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo "Run with sudo"; exit 1; }
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || { echo "Ubuntu required"; exit 1; }
ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == amd64 || "$ARCH" == arm64 ]] || { echo "Unsupported architecture: $ARCH"; exit 1; }
VERSION="${OTELCOL_VERSION:-0.165.0}"
PKG="otelcol-contrib_${VERSION}_linux_${ARCH}.deb"
URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${VERSION}/${PKG}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
apt-get update
apt-get install -y ca-certificates curl
curl --fail --location --retry 3 "$URL" -o "$TMP/$PKG"
apt-get install -y "$TMP/$PKG"
systemctl enable otelcol-contrib
echo "Installed otelcol-contrib ${VERSION}"
