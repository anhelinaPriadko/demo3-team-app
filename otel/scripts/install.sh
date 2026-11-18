#!/usr/bin/env bash
set -Eeuo pipefail

usage() { echo "Usage: install.sh <nginx|app|db-master|db-slave|witness>"; }
ROLE="${1:-}"
case "$ROLE" in nginx|app|db-master|db-slave|witness) ;; *) usage >&2; exit 2 ;; esac
[[ "${EUID}" -eq 0 ]] || { echo "Run as root: sudo bash $0 $ROLE" >&2; exit 1; }

OTELCOL_VERSION="${OTELCOL_VERSION:-0.165.0}"
NGINX_EXPORTER_VERSION="${NGINX_EXPORTER_VERSION:-1.5.3}"
POSTGRES_EXPORTER_VERSION="${POSTGRES_EXPORTER_VERSION:-0.20.1}"

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) GOARCH=amd64; DEBARCH=amd64 ;;
  arm64) GOARCH=arm64; DEBARCH=arm64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

apt-get update
apt-get install -y ca-certificates curl tar gzip acl
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! command -v otelcol-contrib >/dev/null 2>&1; then
  deb="otelcol-contrib_${OTELCOL_VERSION}_linux_${DEBARCH}.deb"
  url="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/${deb}"
  curl --fail --location --retry 3 "$url" --output "$tmp/$deb"
  dpkg -i "$tmp/$deb" || { apt-get -f install -y; dpkg -i "$tmp/$deb"; }
fi
systemctl enable otelcol-contrib

if [[ "$ROLE" == "nginx" ]] && ! command -v nginx-prometheus-exporter >/dev/null 2>&1; then
  archive="nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_${GOARCH}.tar.gz"
  url="https://github.com/nginx/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/${archive}"
  curl --fail --location --retry 3 "$url" --output "$tmp/$archive"
  tar -xzf "$tmp/$archive" -C "$tmp"
  bin="$(find "$tmp" -type f -name nginx-prometheus-exporter -perm -u+x -print -quit)"
  [[ -n "$bin" ]] || { echo "nginx-prometheus-exporter binary not found in archive" >&2; exit 1; }
  install -m 0755 "$bin" /usr/local/bin/nginx-prometheus-exporter
fi

if [[ "$ROLE" == "db-master" || "$ROLE" == "db-slave" ]] && ! command -v postgres_exporter >/dev/null 2>&1; then
  archive="postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-${GOARCH}.tar.gz"
  url="https://github.com/prometheus-community/postgres_exporter/releases/download/v${POSTGRES_EXPORTER_VERSION}/${archive}"
  curl --fail --location --retry 3 "$url" --output "$tmp/$archive"
  tar -xzf "$tmp/$archive" -C "$tmp"
  bin="$(find "$tmp" -type f -name postgres_exporter -perm -u+x -print -quit)"
  [[ -n "$bin" ]] || { echo "postgres_exporter binary not found in archive" >&2; exit 1; }
  install -m 0755 "$bin" /usr/local/bin/postgres_exporter
  if ! id postgres_exporter >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin postgres_exporter
  fi
fi

id otelcol-contrib >/dev/null 2>&1 || { echo "Collector package did not create otelcol-contrib user" >&2; exit 1; }
usermod -aG adm otelcol-contrib
echo "Installed dependencies for role: $ROLE"
