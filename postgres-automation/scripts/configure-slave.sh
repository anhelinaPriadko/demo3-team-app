
#!/bin/bash

set -euo pipefail

POSTGRES_VERSION="16"

echo "=== Installing PostgreSQL ${POSTGRES_VERSION} ==="

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    exit 1
fi

apt-get update

apt-get install -y \
    postgresql-16 \
    postgresql-client-16 \
    postgresql-contrib-16

echo "=== Checking PostgreSQL installation ==="

systemctl enable postgresql
systemctl start postgresql

pg_lsclusters

echo "=== PostgreSQL installation completed ==="


# Configuration

MASTER_IP="10.20.1.4"
MASTER_PORT="5432"

REPLICATION_USER="replicator"
REPLICATION_SLOT="slave1_slot"

PG_DATA="/var/lib/postgresql/${POSTGRES_VERSION}/main"
PGPASS="/var/lib/postgresql/.pgpass"

# Check permissions and secrets
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root."
    exit 1
fi

if [[ -z "${REPLICATION_PASSWORD:-}" ]]; then
    echo "ERROR: REPLICATION_PASSWORD is not set."
    exit 1
fi

echo "=== Checking Master connection ==="

pg_isready -h "$MASTER_IP" -p "$MASTER_PORT"

echo "=== Checking existing data ==="

if [[ -d "$PG_DATA" ]] &&
   [[ -n "$(find "$PG_DATA" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then

    if [[ "${REINITIALIZE_REPLICA:-false}" != "true" ]]; then
        echo "ERROR: Existing PostgreSQL data detected."
        echo "Set REINITIALIZE_REPLICA=true to replace it."
        exit 1
    fi

    echo "=== Moving existing data directory ==="
fi

echo "=== Stopping PostgreSQL ==="

systemctl stop postgresql
HAS_DATA="false"
if [[ -d "$PG_DATA" ]] && [[ -n "$(find "$PG_DATA" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    if [[ "${REINITIALIZE_REPLICA:-false}" != "true" ]]; then
        echo "ERROR: Existing PostgreSQL data detected."
        echo "Set REINITIALIZE_REPLICA=true to replace it."
        exit 1
    fi
    HAS_DATA="true"
    echo "=== Moving existing data directory ==="
fi

echo "=== Preparing data directory ==="

mkdir -p "$PG_DATA"

chown postgres:postgres "$PG_DATA"
chmod 700 "$PG_DATA"

echo "=== Configuring PostgreSQL password file ==="

escape_pgpass() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/:/\\:/g'
}

ESCAPED_PASSWORD=$(escape_pgpass "$REPLICATION_PASSWORD")

install -o postgres -g postgres -m 600 /dev/null "$PGPASS"

printf '%s:%s:*:%s:%s\n' \
    "$MASTER_IP" \
    "$MASTER_PORT" \
    "$REPLICATION_USER" \
    "$ESCAPED_PASSWORD" > "$PGPASS"

echo "=== Creating replica from Master ==="

sudo -u postgres env PGPASSFILE="$PGPASS" \
    pg_basebackup \
    -h "$MASTER_IP" \
    -p "$MASTER_PORT" \
    -U "$REPLICATION_USER" \
    -D "$PG_DATA" \
    -Fp \
    -Xs \
    -P \
    -R \
    -S "$REPLICATION_SLOT"

echo "=== Starting PostgreSQL Slave ==="

systemctl start postgresql

echo "=== Checking recovery status ==="

sudo -u postgres psql -tAc \
    "SELECT pg_is_in_recovery();"

echo "=== Checking WAL receiver ==="

sudo -u postgres psql -x -c \
    "SELECT status, sender_host, sender_port, slot_name
     FROM pg_stat_wal_receiver;"

echo "=== Replica configuration completed ==="

