#!/usr/bin/env bash
set -Eeuo pipefail

ROLE="${1:?Usage: configure.sh <role> <hostname>}"
HOST="${2:?Usage: configure.sh <role> <hostname>}"
case "$ROLE" in nginx|app|db-master|db-slave|witness) ;; *) echo "Unknown role: $ROLE" >&2; exit 2 ;; esac
[[ "$HOST" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid hostname: $HOST" >&2; exit 2; }
[[ "$EUID" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/configs/${ROLE}.yaml"
[[ -f "$CONFIG" ]] || { echo "Missing config: $CONFIG" >&2; exit 1; }
command -v otelcol-contrib >/dev/null 2>&1 || { echo "Install Collector first" >&2; exit 1; }

OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-10.10.0.118:4317}"

install -d -m 0755 /etc/otel-demo3 /etc/systemd/system/otelcol-contrib.service.d
cat >/etc/otel-demo3/otelcol.env <<EOF
OTEL_HOST_NAME=${HOST}
OTEL_EXPORTER_OTLP_ENDPOINT=${OTLP_ENDPOINT}
EOF
chmod 0640 /etc/otel-demo3/otelcol.env
install -m 0644 "$CONFIG" /etc/otelcol-contrib/config.yaml
cat >/etc/systemd/system/otelcol-contrib.service.d/10-demo3.conf <<'EOF'
[Service]
EnvironmentFile=/etc/otel-demo3/otelcol.env
EOF

if [[ "$ROLE" == "nginx" ]]; then
  command -v nginx >/dev/null 2>&1 || { echo "Nginx is not installed" >&2; exit 1; }
  install -d -m 0755 /etc/nginx/conf.d
  STATUS_CONF=/etc/nginx/conf.d/otel-status.conf
  if [[ ! -f "$STATUS_CONF" ]]; then
    cat >"$STATUS_CONF" <<'EOF'
server {
    listen 127.0.0.1:8081;
    server_name localhost;
    location = /stub_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
  fi
  nginx -t
  systemctl reload nginx

  cat >/etc/systemd/system/nginx-prometheus-exporter.service <<'EOF'
[Unit]
Description=NGINX Prometheus Exporter
After=network-online.target nginx.service
Wants=network-online.target
[Service]
User=www-data
Group=www-data
ExecStart=/usr/local/bin/nginx-prometheus-exporter --nginx.scrape-uri=http://127.0.0.1:8081/stub_status --web.listen-address=127.0.0.1:9113
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now nginx-prometheus-exporter
fi

if [[ "$ROLE" == "db-master" || "$ROLE" == "db-slave" ]]; then
  command -v psql >/dev/null 2>&1 || { echo "psql client is missing" >&2; exit 1; }

  # PostgreSQL is started by Patroni; the stock postgresql.service is disabled on these nodes.
  if systemctl is-active --quiet patroni; then
    PG_UNIT=patroni
  elif systemctl is-active --quiet postgresql; then
    PG_UNIT=postgresql
  else
    echo "Neither patroni nor postgresql service is active" >&2
    exit 1
  fi

  echo "Waiting for PostgreSQL on /var/run/postgresql ..."
  for _ in $(seq 1 30); do
    runuser -u postgres -- pg_isready -q -h /var/run/postgresql && break
    sleep 2
  done
  runuser -u postgres -- pg_isready -h /var/run/postgresql >/dev/null || { echo "PostgreSQL is not ready" >&2; exit 1; }

  # Local socket access needs "local all postgres peer" in pg_hba (Patroni config, see README).
  runuser -u postgres -- psql -h /var/run/postgresql -tAc 'SELECT 1' >/dev/null || {
    echo "Cannot connect as postgres over the unix socket. Add 'local all postgres peer' to postgresql.pg_hba in /etc/patroni/config.yml" >&2
    exit 1
  }

  # Only the leader accepts writes. The role then replicates to the replica by itself.
  IS_LEADER=false
  if [[ "$PG_UNIT" == "patroni" ]]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8008/primary || true)"
    [[ "$code" == "200" ]] && IS_LEADER=true
  else
    [[ "$(runuser -u postgres -- psql -h /var/run/postgresql -tAc 'SELECT pg_is_in_recovery()')" == "f" ]] && IS_LEADER=true
  fi

  id postgres_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin postgres_exporter

  if [[ "$IS_LEADER" == "true" ]]; then
    echo "Leader: creating monitoring role otel_monitor (no password, peer auth via pg_ident map 'otel')"
    runuser -u postgres -- psql -h /var/run/postgresql -v ON_ERROR_STOP=1 \
      -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='otel_monitor') THEN CREATE ROLE otel_monitor LOGIN; END IF; END \$\$;" \
      -c "ALTER ROLE otel_monitor LOGIN PASSWORD NULL;" \
      -c "GRANT pg_monitor TO otel_monitor;"
  else
    echo "Replica: role otel_monitor comes from the leader through replication"
  fi

  # No password anywhere: the exporter runs as OS user postgres_exporter, which pg_ident maps to otel_monitor.
  install -d -o root -g postgres_exporter -m 0750 /etc/postgres-exporter
  cat >/etc/postgres-exporter/exporter.env <<'EOF'
DATA_SOURCE_NAME="user=otel_monitor host=/var/run/postgresql dbname=postgres sslmode=disable"
EOF
  chown root:postgres_exporter /etc/postgres-exporter/exporter.env
  chmod 0640 /etc/postgres-exporter/exporter.env

  cat >/etc/systemd/system/postgres-exporter.service <<'EOF'
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network-online.target patroni.service postgresql.service
Wants=network-online.target
[Service]
User=postgres_exporter
Group=postgres_exporter
EnvironmentFile=/etc/postgres-exporter/exporter.env
ExecStart=/usr/local/bin/postgres_exporter --web.listen-address=127.0.0.1:9187
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=-/run/postgresql
[Install]
WantedBy=multi-user.target
EOF

  # Grant Collector read access to current and future PostgreSQL log files.
  [[ -d /var/log/postgresql ]] || install -d -o postgres -g adm -m 1775 /var/log/postgresql
  setfacl -m u:otelcol-contrib:rx /var/log/postgresql
  setfacl -d -m u:otelcol-contrib:r /var/log/postgresql
  find /var/log/postgresql -type f -name '*.log' -exec setfacl -m u:otelcol-contrib:r {} +

  systemctl daemon-reload
  systemctl enable postgres-exporter
  systemctl restart postgres-exporter
fi

# Group membership (adm, systemd-journal) takes effect after the restart below.
systemctl daemon-reload
# The config uses ${env:...}: validate with the same variables systemd will pass
( set -a; . /etc/otel-demo3/otelcol.env; set +a; otelcol-contrib validate --config="/etc/otelcol-contrib/config.yaml" )
systemctl restart otelcol-contrib
systemctl is-active --quiet otelcol-contrib
echo "Configured Collector role=$ROLE host=$HOST"
