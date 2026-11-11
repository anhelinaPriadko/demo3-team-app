
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
SLAVE_IP="10.20.1.3/32"

REPLICATION_USER="replicator"
REPLICATION_SLOT="slave1_slot"

PG_CONF="/etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf"

# Check permissions and secrets
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root."
    exit 1
fi

if [[ -z "${REPLICATION_PASSWORD:-}" ]]; then
    echo "ERROR: REPLICATION_PASSWORD is not set."
    exit 1
fi

echo "=== Configuring PostgreSQL Master ==="

# Enable replication settings
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
ALTER SYSTEM SET listen_addresses = '*';
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
SQL

echo "=== Configuring pg_hba.conf ==="

HBA_RULE="host replication ${REPLICATION_USER} ${SLAVE_IP} scram-sha-256"

if ! grep -Fxq "$HBA_RULE" "$PG_HBA"; then
    echo "$HBA_RULE" >> "$PG_HBA"
fi

echo "=== Creating replication user ==="

sudo -u postgres psql \
    -v ON_ERROR_STOP=1 \
    -v replication_password="$REPLICATION_PASSWORD" <<'SQL'

SELECT format(
    'CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD %L',
    :'replication_password'
)
WHERE NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = 'replicator'
)\gexec

ALTER ROLE replicator
WITH LOGIN REPLICATION PASSWORD :'replication_password';

SQL

echo "=== Creating replication slot ==="

sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -c "SELECT pg_create_physical_replication_slot('${REPLICATION_SLOT}')
        WHERE NOT EXISTS (
            SELECT FROM pg_replication_slots
            WHERE slot_name = '${REPLICATION_SLOT}'
        );"

echo "=== Restarting PostgreSQL ==="

systemctl restart postgresql

echo "=== Master verification ==="

pg_lsclusters

sudo -u postgres psql -c \
    "SELECT rolname, rolreplication
     FROM pg_roles
     WHERE rolname = '${REPLICATION_USER}';"

echo "=== Master configuration completed ==="

