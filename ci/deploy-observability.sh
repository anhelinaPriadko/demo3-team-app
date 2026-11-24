#!/usr/bin/env bash
set -Eeuo pipefail

SSH_USER=sa_116687368623049818165
opts=(
  -i /home/gitlab-runner/.ssh/gcp_deploy
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
)

python3 - <<'PY' > inventory/otel.tsv
import ipaddress
import json
import re

ips = json.load(open("inventory/ips.json"))
names = json.load(open("inventory/names.json"))

roles = {
    "nginx": "nginx",
    "db_master": "db-master",
    "db_slave": "db-slave",
    "db_witness": "witness",
}

for key, ip in ips.items():
    role = "app" if key.startswith("app-") else roles[key]
    assert re.fullmatch(r"[A-Za-z0-9._-]+", names[key])
    print(
        ipaddress.IPv4Address(ip),
        role,
        names[key],
        sep="\t",
    )
PY

while IFS=$'\t' read -r ip role vm; do
  echo "Deploying Collector: $vm ($role)"

  tar -czf - otel | ssh "${opts[@]}" "$SSH_USER@$ip" \
    'sudo -n tar --no-same-owner -xzf - -C /tmp'

  ssh "${opts[@]}" "$SSH_USER@$ip" \
    "sudo -n bash /tmp/otel/scripts/deploy.sh '$role' '$vm'"
done < inventory/otel.tsv