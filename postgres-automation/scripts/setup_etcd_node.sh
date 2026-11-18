#!/usr/bin/env bash
set -Eeuo pipefail

CURRENT_IP="10.20.1.6"
ETCD_NAME="etcd3"
ETCD_ENDPOINTS="http://10.20.1.4:2379,http://10.20.1.3:2379,http://10.20.1.6:2379"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    exit 1
fi

echo "=== Installing etcd on dedicated node ($CURRENT_IP) ==="
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

echo "=== Checking etcd cluster health ==="
etcdctl --endpoints="$ETCD_ENDPOINTS" endpoint health

echo "=== etcd node setup completed successfully ==="
