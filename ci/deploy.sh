#!/usr/bin/env bash
set -Eeuo pipefail

mode=${1:-deploy}
[[ $mode == deploy || $mode == rollback ]] || exit 2

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

remote() {
  local ip=$1
  shift
  ssh "${opts[@]}" "$SSH_USER@$ip" "$@"
}

python3 - <<'PY'
import ipaddress
import json
import pathlib

ips = json.load(open("inventory/ips.json"))
apps = json.load(open("inventory/apps.json"))

assert apps and len(apps) == len(set(apps)), \
    "Empty or duplicate app addresses"

for ip in list(ips.values()) + apps:
    ipaddress.IPv4Address(ip)

pathlib.Path("inventory/apps.txt").write_text(
    "\n".join(apps) + "\n"
)
PY

mapfile -t apps < inventory/apps.txt

nginx=$(jq -er '.nginx' inventory/ips.json)
db1=$(jq -er '.db_master' inventory/ips.json)
db2=$(jq -er '.db_slave' inventory/ips.json)

dir="/tmp/cinema-ci-$CI_JOB_ID"
release="$CI_PIPELINE_ID-$CI_JOB_ID-$CI_COMMIT_SHORT_SHA"
image="demo3-cinema:$release"

remote "$nginx" "mkdir -p '$dir'"
scp "${opts[@]}" ci/nginx-upstream.py "$SSH_USER@$nginx:$dir/"

upstream() {
  remote "$nginx" "sudo -n python3 '$dir/nginx-upstream.py' $*"
}

upstream check

for ip in "${apps[@]}"; do
  remote "$ip" "mkdir -p '$dir'"
  scp "${opts[@]}" ci/app-host.sh "$SSH_USER@$ip:$dir/"
done

host() {
  local ip=$1
  shift
  remote "$ip" "sudo -n bash '$dir/app-host.sh' $*"
}

targets=()

if [[ $mode == deploy ]]; then
  docker info >/dev/null
  docker build -t "$image" .

  for ip in "${apps[@]}"; do
    host "$ip" prepare

    docker save "$image" | gzip | remote "$ip" \
      "bash -o pipefail -c 'gunzip | sudo -n docker load'"

    host "$ip" stage "$release" "$image" "$db1" "$db2"
    targets+=("$release")
  done

  for ip in "${apps[@]}"; do
    host "$ip" snapshot "$CI_PIPELINE_ID"
  done
else
  for ip in "${apps[@]}"; do
    targets+=("$(host "$ip" previous "$CI_PIPELINE_ID")")
  done

  found=false
  for target in "${targets[@]}"; do
    [[ $target == NONE ]] || found=true
  done

  [[ $found == true ]] || {
    echo 'First deployment: no previous release to restore'
    exit 1
  }
fi

states=()
unhealthy=()
healthy=()

for i in "${!apps[@]}"; do
  if host "${apps[$i]}" probe; then
    states+=("${apps[$i]}=up")
    healthy+=("$i")
  else
    states+=("${apps[$i]}=down")
    unhealthy+=("$i")
  fi
done

upstream sync "${states[@]}"

for i in "${unhealthy[@]}" "${healthy[@]}"; do
  ip=${apps[$i]}
  echo "$mode: $ip -> ${targets[$i]}"

  was_healthy=false

  if host "$ip" probe; then
    was_healthy=true

    if ((${#apps[@]} > 1)); then
      peer=false

      for other in "${apps[@]}"; do
        if [[ $other != "$ip" ]] && host "$other" probe; then
          peer=true
          break
        fi
      done

      [[ $peer == true ]] || {
        echo 'No healthy peer; refusing to stop the last healthy app'
        exit 1
      }
    fi
  fi

  upstream down "$ip"

  if [[ $was_healthy == true ]]; then
    sleep 65
  fi

  if [[ ${targets[$i]} == NONE ]]; then
    host "$ip" remove

  elif host "$ip" activate "${targets[$i]}"; then
    upstream up "$ip"

  else
    if host "$ip" probe; then
      upstream up "$ip"
    fi

    echo 'Deployment stopped. Failed node attempted local recovery.' >&2
    echo 'Use rollback_application to restore earlier updated nodes.' >&2
    exit 1
  fi
done

echo "$mode completed"