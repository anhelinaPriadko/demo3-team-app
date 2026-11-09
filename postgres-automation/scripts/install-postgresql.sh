#!/usr/bin/env bash
set -Eeuo pipefail

PG_VERSION="${PG_VERSION:-16}"
PATRONI_VERSION="${PATRONI_VERSION:-4.0.6}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

echo "[1/5] Updating packages..."
apt-get update
apt-get install -y \
  curl wget ca-certificates gnupg lsb-release \
  python3 python3-venv python3-dev \
  build-essential libpq-dev \
  postgresql-common postgresql-client-"$PG_VERSION" \
  postgresql-"$PG_VERSION" \
  python3-psycopg2

echo "[2/5] Installing Patroni..."
python3 -m venv /opt/patroni/venv
/opt/patroni/venv/bin/pip install --upgrade pip
/opt/patroni/venv/bin/pip install \
  "patroni[etcd3]==${PATRONI_VERSION}" \
  psycopg2-binary

echo "[3/5] Creating directories..."
install -d -o postgres -g postgres -m 700 \
  "/var/lib/postgresql/${PG_VERSION}/patroni"

install -d -o postgres -g postgres -m 750 /var/log/patroni
install -d -o root -g root -m 755 /etc/patroni

echo "[4/5] Preventing the default PostgreSQL cluster from starting..."
systemctl disable --now postgresql.service || true
systemctl disable --now "postgresql@${PG_VERSION}-main.service" || true

echo "[5/5] Creating Patroni systemd service..."

cat > /etc/systemd/system/patroni.service <<'SERVICE'
[Unit]
Description=Patroni PostgreSQL HA Cluster
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/opt/patroni/venv/bin/patroni /etc/patroni/patroni.yml
KillMode=process
TimeoutSec=30
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable patroni

echo "PostgreSQL and Patroni installed."
echo "Patroni is enabled but not started yet."
