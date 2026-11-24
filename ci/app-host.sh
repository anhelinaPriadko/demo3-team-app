#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

base=/opt/cinema
action=${1:?action required}
arg=${2:-}
[[ $EUID == 0 ]] || exit 1

probe() {
  [[ $(curl -s --max-time 5 -o /dev/null -w '%{http_code}' \
    http://127.0.0.1:8080/api/v1/movies) == 200 ]]
}

start_release() {
  local dir=$1

  if docker container inspect cinema-app >/dev/null 2>&1; then
    docker stop -t 30 cinema-app >/dev/null || return 1
    docker rm cinema-app >/dev/null || return 1
  fi

  docker run -d --name cinema-app --restart unless-stopped \
    --env-file "$dir/app.env" \
    -e SPRING_PROFILES_ACTIVE=prod \
    -e SPRING_SQL_INIT_MODE=never \
    -e SERVER_SHUTDOWN=graceful \
    -e 'JAVA_TOOL_OPTIONS=-javaagent:/opt/opentelemetry-javaagent.jar -XX:MaxRAMPercentage=60.0' \
    -e LOGGING_FILE_NAME=/var/log/cinema/app.log \
    -e LOGGING_LOGBACK_ROLLINGPOLICY_MAX_FILE_SIZE=10MB \
    -e LOGGING_LOGBACK_ROLLINGPOLICY_MAX_HISTORY=7 \
    -e OTEL_SERVICE_NAME=demo3-java-app \
    -e "OTEL_RESOURCE_ATTRIBUTES=deployment.environment=demo3,host.name=$(hostname)" \
    -e OTEL_EXPORTER_OTLP_ENDPOINT=http://10.10.0.118:4318 \
    -e OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
    -e OTEL_TRACES_EXPORTER=otlp \
    -e OTEL_METRICS_EXPORTER=otlp \
    -e OTEL_LOGS_EXPORTER=otlp \
    --memory=1200m \
    --log-opt max-size=10m \
    --log-opt max-file=3 \
    -p 8080:8080 \
    -v /opt/cinema/uploads:/app/uploads \
    -v /var/log/cinema:/var/log/cinema \
    "$(cat "$dir/image")" >/dev/null || return 1

  for ((i=0; i<80; i++)); do
    if probe; then return 0; fi
    sleep 3
  done

  return 1
}

case "$action" in
  prepare)
    if ! command -v docker >/dev/null || ! command -v curl >/dev/null; then
      apt-get -o DPkg::Lock::Timeout=300 update
      DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 \
        install -y docker.io curl
    fi

    systemctl enable --now docker

    if [[ ! -L $base/current ]] && { \
      ss -H -ltn 'sport = :8080' | grep -q . || \
      docker container inspect cinema-app >/dev/null 2>&1; }; then
      echo 'Unmanaged application already uses port 8080 or cinema-app' >&2
      exit 1
    fi

    install -d -m 700 "$base/releases" "$base/rollback"
    install -d -m 755 "$base/uploads" /var/log/cinema
    ;;

  stage)
    [[ $arg =~ ^[0-9]+-[0-9]+-[a-f0-9]+$ ]] || exit 2

    python3 - "$base/releases/$arg" "${3:?image}" "${4:?db1}" "${5:?db2}" <<'PY'
import base64
import ipaddress
import json
import os
import pathlib
import sys
import urllib.request

def get(url, headers):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)

token = get(
    "http://metadata.google.internal/computeMetadata/v1/"
    "instance/service-accounts/default/token",
    {"Metadata-Flavor": "Google"},
)["access_token"]

def secret(name):
    result = get(
        "https://secretmanager.googleapis.com/v1/"
        "projects/demo3-team1/secrets/"
        + name + "/versions/latest:access",
        {"Authorization": "Bearer " + token},
    )
    value = base64.b64decode(result["payload"]["data"]).decode()
    if not value or any(c in value for c in "\r\n\x00"):
        raise ValueError("Invalid secret: " + name)
    return value

db1, db2 = (
    str(ipaddress.IPv4Address(x))
    for x in sys.argv[3:5]
)

env = {
    "SPRING_DATASOURCE_URL":
        f"jdbc:postgresql://{db1}:5432,{db2}:5432/demo3_app"
        "?targetServerType=primary&connectTimeout=5",
    "SPRING_DATASOURCE_USERNAME":
        secret("demo3-db-appuser-username"),
    "SPRING_DATASOURCE_PASSWORD":
        secret("demo3-db-appuser-password"),
}

path = pathlib.Path(sys.argv[1])
path.mkdir(mode=0o700, parents=True, exist_ok=True)

with open(path / "app.env.tmp", "w") as file:
    for key, value in env.items():
        file.write(key + "=" + value + "\n")

os.replace(path / "app.env.tmp", path / "app.env")
(path / "image").write_text(sys.argv[2] + "\n")
print("Release staged; secret values hidden")
PY
    ;;

  probe)
    probe
    ;;

  snapshot)
    [[ $arg =~ ^[0-9]+$ ]] || exit 2

    if [[ ! -f $base/rollback/$arg ]]; then
      if [[ -L $base/current ]]; then
        basename "$(readlink -f "$base/current")" > "$base/rollback/$arg"
      else
        echo NONE > "$base/rollback/$arg"
      fi
    fi

    echo "$arg" > "$base/last-pipeline"
    ;;

  previous)
    [[ $arg =~ ^[0-9]+$ ]] || exit 2

    [[ $(cat "$base/last-pipeline") == "$arg" ]] || {
      echo 'A newer deployment exists; use its rollback job' >&2
      exit 1
    }

    cat "$base/rollback/$arg"
    ;;

  remove)
    if docker container inspect cinema-app >/dev/null 2>&1; then
      docker stop -t 30 cinema-app >/dev/null
      docker rm cinema-app >/dev/null
    fi

    rm -f "$base/current"
    ;;

  activate)
    [[ $arg =~ ^[0-9]+-[0-9]+-[a-f0-9]+$ ]] || exit 2

    new="$base/releases/$arg"
    [[ -s $new/app.env && -s $new/image ]] || exit 2
    docker image inspect "$(cat "$new/image")" >/dev/null

    old=''
    if [[ -L $base/current ]]; then
      old=$(readlink -f "$base/current")
    fi

    if [[ $old == "$new" ]] && probe; then
      exit 0
    fi

    if start_release "$new"; then
      ln -sfn "$new" "$base/current"
      echo "Release $arg: healthy"
    else
      echo "Release $arg failed health check" >&2

      if [[ -n $old ]]; then
        start_release "$old" || {
          echo 'Old release also failed' >&2
          exit 1
        }
        echo 'Old release restored' >&2
      else
        docker rm -f cinema-app >/dev/null 2>&1 || true
      fi

      exit 1
    fi
    ;;

  *)
    exit 2
    ;;
esac