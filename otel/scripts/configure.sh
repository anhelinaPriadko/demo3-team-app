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

install -d -m 0755 /etc/otel-demo3 /etc/systemd/system/otelcol-contrib.service.d
cat >/etc/otel-demo3/otelcol.env <<EOF
OTEL_HOST_NAME=${HOST}
OTEL_EXPORTER_OTLP_ENDPOINT=10.10.0.118:4317
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
  systemctl is-active --quiet postgresql || { echo "PostgreSQL service is not active" >&2; exit 1; }
  id postgres_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin postgres_exporter

  # Generate a dedicated monitoring credential; it is stored only in a root-owned local env file.
  install -d -o root -g postgres_exporter -m 0750 /etc/postgres-exporter
  if [[ ! -s /etc/postgres-exporter/exporter.env ]]; then
    PW="$(openssl rand -hex 32)"
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='otel_monitor') THEN EXECUTE format('CREATE ROLE otel_monitor LOGIN PASSWORD %L', '${PW}'); END IF; END \$\$;"
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "ALTER ROLE otel_monitor LOGIN PASSWORD '${PW}'; GRANT pg_monitor TO otel_monitor;"
    cat >/etc/postgres-exporter/exporter.env <<EOF
DATA_SOURCE_URI=127.0.0.1:5432/postgres?sslmode=disable
DATA_SOURCE_USER=otel_monitor
DATA_SOURCE_PASS=${PW}
EOF
    chown root:postgres_exporter /etc/postgres-exporter/exporter.env
    chmod 0640 /etc/postgres-exporter/exporter.env
    unset PW
  else
    echo "Reusing existing local PostgreSQL exporter credentials."
  fi

  cat >/etc/systemd/system/postgres-exporter.service <<'EOF'
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network-online.target postgresql.service
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
[Install]
WantedBy=multi-user.target
EOF

  # Grant Collector read access to current and future PostgreSQL log files.
  if [[ -d /var/log/postgresql ]]; then
    setfacl -m u:otelcol-contrib:rx /var/log/postgresql
    setfacl -d -m u:otelcol-contrib:rx /var/log/postgresql
    find /var/log/postgresql -type f -name '*.log' -exec setfacl -m u:otelcol-contrib:r {} +
  fi

  systemctl daemon-reload
  systemctl enable --now postgres-exporter
fi

# Collector must read standard system logs. Group membership takes effect after restart.
systemctl daemon-reload
otelcol-contrib validate --config="/etc/otelcol-contrib/config.yaml"
systemctl restart otelcol-contrib
systemctl is-active --quiet otelcol-contrib
echo "Configured Collector role=$ROLE host=$HOST"
