#!/usr/bin/env bash
set -Eeuo pipefail
ROLE="${1:?Usage: deploy.sh <role> <hostname>}"
HOST="${2:?Usage: deploy.sh <role> <hostname>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$EUID" -eq 0 ]] || { echo "Run as root: sudo bash $0 $ROLE $HOST" >&2; exit 1; }
bash "$ROOT/scripts/install.sh" "$ROLE"
bash "$ROOT/scripts/configure.sh" "$ROLE" "$HOST"
bash "$ROOT/scripts/verify.sh"
