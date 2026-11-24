#!/usr/bin/env bash
set -Eeuo pipefail

SSH_USER=sa_116687368623049818165
SSH_KEY=/home/gitlab-runner/.ssh/gcp_deploy

test -r "$SSH_KEY"

opts=(
  -i "$SSH_KEY"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=2
)

python3 - <<'PY' > inventory/hosts.tsv
import ipaddress
import json

ips = json.load(open("inventory/ips.json"))

apps = sorted(
    (key for key in ips if key.startswith("app-")),
    key=lambda key: int(key.split("-")[1]),
)
assert apps, "No application VMs in inventory"

endpoints = ",".join(
    "http://" + str(ipaddress.IPv4Address(ips[key])) + ":2379"
    for key in ("db_master", "db_slave", "db_witness")
)

for key in ["nginx", *apps, "db_master", "db_slave", "db_witness"]:
    print(
        key,
        ipaddress.IPv4Address(ips[key]),
        endpoints,
        sep="\t",
    )
PY

failed=0

while IFS=$'\t' read -r role ip endpoints; do
  printf '\n=== %s (%s) ===\n' "$role" "$ip"

  if ! ssh "${opts[@]}" "$SSH_USER@$ip" \
    "sudo -n bash -s -- '$role' '$endpoints'" <<'REMOTE'
set -uo pipefail

role=$1
endpoints=$2
bad=0

hostname
echo 'SSH + sudo: OK'

case "$role" in
  nginx)
    if command -v nginx >/dev/null; then
      nginx -t || bad=1
      systemctl is-active nginx || bad=1
    else
      echo 'Nginx is not installed yet'
      bad=1
    fi
    ;;

  app-*)
    if command -v docker >/dev/null; then
      docker --version
      docker ps --format '{{.Names}}: {{.Status}}'
    else
      echo 'Docker is not installed yet; app deployment must install it'
    fi

    ss -ltn 'sport = :8080'

    python3 - <<'PY' || bad=1
import base64
import json
import sys
import urllib.request


def get(url, headers):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


try:
    credentials = get(
        "http://metadata.google.internal/computeMetadata/v1/"
        "instance/service-accounts/default/token",
        {"Metadata-Flavor": "Google"},
    )

    headers = {
        "Authorization": "Bearer " + credentials["access_token"]
    }

    for name in (
        "demo3-db-appuser-username",
        "demo3-db-appuser-password",
    ):
        url = (
            "https://secretmanager.googleapis.com/v1/"
            "projects/demo3-team1/secrets/"
            + name
            + "/versions/latest:access"
        )

        result = get(url, headers)
        value = base64.b64decode(result["payload"]["data"])

        if not value or b"\n" in value or b"\r" in value:
            raise ValueError(name + ": empty or multiline secret")

        print(name + ": access OK; value hidden")

except Exception as error:
    print("Secret access check failed:", str(error), file=sys.stderr)
    sys.exit(1)
PY
    ;;

  db_master|db_slave)
    systemctl is-active etcd || bad=1
    systemctl is-active patroni || bad=1

    if command -v psql >/dev/null; then
      runuser -u postgres -- psql \
        -X -d postgres -v ON_ERROR_STOP=1 \
        -c "SELECT pg_is_in_recovery() AS is_replica;" || bad=1

      found=$(runuser -u postgres -- psql \
        -X -d postgres -v ON_ERROR_STOP=1 -tAc \
        "SELECT EXISTS (
          SELECT FROM pg_database WHERE datname='demo3_app'
        );") || bad=1

      if [[ ${found:-} == t ]]; then
        echo 'Database demo3_app: exists'
      else
        echo 'Database demo3_app: NOT confirmed'
        bad=1
      fi
    else
      echo 'PostgreSQL client is missing'
      bad=1
    fi
    ;;

  db_witness)
    systemctl is-active etcd || bad=1

    ETCDCTL_API=3 timeout 20s etcdctl \
      --endpoints="$endpoints" \
      endpoint health || bad=1
    ;;
esac

exit "$bad"
REMOTE
  then
    failed=1
  fi
done < inventory/hosts.tsv

exit "$failed"