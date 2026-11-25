#!/usr/bin/env bash
set -Eeuo pipefail

CURRENT_IP="10.20.1.4"
NODE_NAME="pg_node_1"
ETCD_NAME="etcd1"
CLUSTER_NAME="demo3-pg-cluster"
ETCD_ENDPOINTS="http://10.20.1.4:2379,http://10.20.1.3:2379,http://10.20.1.6:2379"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    exit 1
fi

echo "=== 1. Installing etcd on Master node ==="
apt-get update
apt-get install -y etcd-server etcd-client

cat <<EOF > /etc/default/etcd
ETCD_NAME="${ETCD_NAME}"
ETCD_DATA_DIR="/var/lib/etcd/default"
ETCD_LISTEN_PEER_URLS="http://${CURRENT_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="http://${CURRENT_IP}:2379,http://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${CURRENT_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://${CURRENT_IP}:2379"
ETCD_INITIAL_CLUSTER_TOKEN="pg-ha-etcd"
ETCD_INITIAL_CLUSTER="etcd1=http://10.20.1.4:2380,etcd2=http://10.20.1.3:2380,etcd3=http://10.20.1.6:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

systemctl enable --now etcd
systemctl restart etcd

echo "=== 2. Installing PostgreSQL 16, Patroni and dependencies ==="
apt-get install -y \
    postgresql-16 \
    postgresql-client-16 \
    patroni \
    python3-venv \
    python3-pip \
    python3-psycopg2 \
    python3-etcd

python3 -m venv --system-site-packages /opt/patroni-3.3.3

/opt/patroni-3.3.3/bin/pip install \
    "patroni[etcd3]==3.3.3"

systemctl stop postgresql
systemctl disable postgresql

rm -rf /var/lib/postgresql/16/main
install -d -o postgres -g postgres -m 700 /var/lib/postgresql/16/main

echo "=== 3. Creating Patroni configuration ==="
mkdir -p /etc/patroni

cat <<EOF > /etc/patroni/config.yml
scope: ${CLUSTER_NAME}
namespace: /service/
name: ${NODE_NAME}

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${CURRENT_IP}:8008

etcd3:
  hosts:
    - 10.20.1.4:2379
    - 10.20.1.3:2379
    - 10.20.1.6:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_log_hints: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        logging_collector: "on"
        log_directory: /var/log/postgresql
        log_filename: postgresql-%a.log
        log_truncate_on_rotation: "on"
        log_rotation_age: 1d
        log_file_mode: "0640"

  initdb:
    - encoding: UTF8
    - data-checksums


postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${CURRENT_IP}:5432
  data_dir: /var/lib/postgresql/16/main
  bin_dir: /usr/lib/postgresql/16/bin
  config_dir: /etc/postgresql/16/main
  pgpass: /var/lib/postgresql/.pgpass
  authentication:
    replication:
      username: replicator
      password: "StrongReplicationPassword123!"
    superuser:
      username: postgres
      password: "StrongSuperuserPassword123!"
  parameters:
    unix_socket_directories: '/var/run/postgresql'
  pg_hba:
   - local all postgres peer
   - local all otel_monitor peer map=otel
   - host replication replicator 10.20.1.0/24 scram-sha-256
   - host replication replicator 127.0.0.1/32 scram-sha-256
   - host all all 10.20.1.0/24 scram-sha-256
   - host all all 127.0.0.1/32 scram-sha-256
  pg_ident:
    - otel postgres_exporter otel_monitor
  
EOF

chown -R postgres:postgres /etc/patroni
chmod 640 /etc/patroni/config.yml

echo "=== 4. Starting Patroni on Master ==="
systemctl enable --now patroni

echo "=== Master node setup completed successfully! ==="
