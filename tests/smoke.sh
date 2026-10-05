#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
export KAVOSHRUST_LIB_ONLY=1
export KAVOSHRUST_INSTALL_DIR="$TMP_DIR"
export KAVOSHRUST_BACKUP_DIR="$TMP_DIR/backups"
export KAVOSHRUST_MANAGER_BIN="$TMP_DIR/kavoshrust"
export KAVOSHRUST_LOG_FILE="$TMP_DIR/test.log"

cleanup() {
  if [[ -f "$TMP_DIR/compose.yml" && -f "$TMP_DIR/.env" ]]; then
    (cd "$TMP_DIR" && docker compose --env-file .env -f compose.yml down -v --remove-orphans) >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# shellcheck source=../install.sh
source "$ROOT_DIR/install.sh"

mkdir -p "$DATA_DIR"
write_env "127.0.0.1" 42116 43117 0 0 N
generate_caddy_files
generate_compose

cd "$TMP_DIR"
docker compose --env-file .env -f compose.yml pull
docker compose --env-file .env -f compose.yml up -d

for _ in $(seq 1 45); do
  [[ -s "$DATA_DIR/id_ed25519.pub" ]] && break
  sleep 1
done

[[ -s "$DATA_DIR/id_ed25519.pub" ]]
docker ps --format '{{.Names}}' | grep -qx 'kavoshrust-hbbs'
docker ps --format '{{.Names}}' | grep -qx 'kavoshrust-hbbr'

for spec in \
  "42115:tcp" \
  "42116:tcp" \
  "42116:udp" \
  "43117:tcp"
do
  port=${spec%:*}
  proto=${spec#*:}
  if [[ "$proto" == tcp ]]; then
    ss -H -lnt "sport = :$port" | grep -q .
  else
    ss -H -lnu "sport = :$port" | grep -q .
  fi
done

if ss -H -lnt "sport = :42118" | grep -q .; then
  echo "Unexpected host listener on disabled hbbs WebSocket port" >&2
  exit 1
fi
if ss -H -lnt "sport = :43119" | grep -q .; then
  echo "Unexpected host listener on disabled hbbr WebSocket port" >&2
  exit 1
fi

docker logs kavoshrust-hbbs --tail 100
docker logs kavoshrust-hbbr --tail 100

echo "RustDesk container smoke test passed on custom ports."
