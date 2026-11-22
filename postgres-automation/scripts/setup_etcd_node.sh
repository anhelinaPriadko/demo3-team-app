#!/usr/bin/env bash
set -Eeuo pipefail

CURRENT_IP="10.20.1.6"
ETCD_NAME="etcd3"
ETCD_ENDPOINTS="http://10.20.1.4:2379,http://10.20.1.3:2379,http://10.20.1.6:2379"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root." >&2
    exit 1
fi

echo "=== Installing etcd on dedicated node ($CURRENT_IP) ==="
apt-get update
apt-get install -y etcd-server etcd-client

if [[ -d /var/lib/etcd/default/member ]]; then
    CLUSTER_STATE="existing"
else
    CLUSTER_STATE="new"
fi

cat <<EOF > /etc/default/etcd
ETCD_NAME="${ETCD_NAME}"
ETCD_DATA_DIR="/var/lib/etcd/default"
ETCD_LISTEN_PEER_URLS="http://${CURRENT_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="http://${CURRENT_IP}:2379,http://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${CURRENT_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://${CURRENT_IP}:2379"
ETCD_INITIAL_CLUSTER_TOKEN="pg-ha-etcd"
ETCD_INITIAL_CLUSTER="etcd1=http://10.20.1.4:2380,etcd2=http://10.20.1.3:2380,etcd3=http://10.20.1.6:2380"
ETCD_INITIAL_CLUSTER_STATE="${CLUSTER_STATE}"
EOF

systemctl enable etcd
systemctl restart etcd

echo "=== Waiting for local etcd on 127.0.0.1:2379 ==="
for i in $(seq 1 30); do
    if ETCDCTL_API=3 etcdctl --endpoints="http://127.0.0.1:2379" endpoint health >/dev/null 2>&1; then
        break
    fi
    if [[ "$i" -eq 30 ]]; then
        echo "ERROR: Local etcd did not become healthy in time." >&2
        exit 1
    fi
    sleep 2
done

echo "=== Checking etcd cluster health ==="
ETCDCTL_API=3 etcdctl --endpoints="$ETCD_ENDPOINTS" endpoint health --write-out=table || \
    echo "WARNING: Not all etcd endpoints are healthy yet. Check ports 2379/2380 and GCP firewall." >&2

echo "=== etcd node setup completed successfully ==="
