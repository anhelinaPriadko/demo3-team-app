
#!/bin/bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root."
    exit 1
fi

echo "=== PostgreSQL cluster status ==="

pg_lsclusters

echo
echo "=== Recovery status ==="

RECOVERY=$(sudo -u postgres psql -tAc \
    "SELECT pg_is_in_recovery();")

echo "pg_is_in_recovery(): $RECOVERY"

if [[ "$RECOVERY" == "t" ]]; then

    echo
    echo "=== Slave: WAL receiver ==="

    sudo -u postgres psql -x -c \
        "SELECT status, sender_host, sender_port, slot_name
         FROM pg_stat_wal_receiver;"

else

    echo
    echo "=== Master: Connected replicas ==="

    sudo -u postgres psql -x -c \
        "SELECT application_name,
                client_addr,
                state,
                sync_state,
                sent_lsn,
                replay_lsn
         FROM pg_stat_replication;"

    echo
    echo "=== Replication slots ==="

    sudo -u postgres psql -x -c \
        "SELECT slot_name, active, restart_lsn
         FROM pg_replication_slots;"
fi
