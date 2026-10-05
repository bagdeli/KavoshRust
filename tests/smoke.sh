#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
HBBS_PID=""
HBBR_PID=""

cleanup(){
  [[ -n "$HBBS_PID" ]] && kill "$HBBS_PID" >/dev/null 2>&1 || true
  [[ -n "$HBBR_PID" ]] && kill "$HBBR_PID" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

export KAVOSHRUST_LIB_ONLY=1
export KAVOSHRUST_TEST_MODE=1
export KAVOSHRUST_INSTALL_DIR="$TMP/kavoshrust"
export KAVOSHRUST_BACKUP_DIR="$TMP/backups"
export KAVOSHRUST_MANAGER_BIN="$TMP/kavoshrust-manager"
export KAVOSHRUST_LOG_FILE="$TMP/test.log"
export KAVOSHRUST_SYSTEMD_DIR="$TMP/systemd"
export KAVOSHRUST_NGINX_SITE="$TMP/nginx/kavoshrust.conf"
export KAVOSHRUST_ACME_WEBROOT="$TMP/acme"

# shellcheck source=../install.sh
source "$ROOT/install.sh"

mkdir -p "$INSTALL_DIR" "$DATA_DIR"
install_rustdesk_binaries

ID_PORT=42116
RELAY_PORT=43117
validate_layout "$ID_PORT" "$RELAY_PORT" install

cd "$DATA_DIR"
"$BIN_DIR/hbbs" -p "$ID_PORT" -r "127.0.0.1:$RELAY_PORT" -k _ >"$TMP/hbbs.log" 2>&1 &
HBBS_PID=$!

for _ in $(seq 1 30); do
  [[ -s "$DATA_DIR/id_ed25519.pub" ]] && break
  sleep 1
done
[[ -s "$DATA_DIR/id_ed25519.pub" ]]

"$BIN_DIR/hbbr" -p "$RELAY_PORT" -k _ >"$TMP/hbbr.log" 2>&1 &
HBBR_PID=$!

sleep 2
kill -0 "$HBBS_PID"
kill -0 "$HBBR_PID"

for spec in \
  "42115:tcp" \
  "42116:tcp" \
  "42116:udp" \
  "42118:tcp" \
  "43117:tcp" \
  "43119:tcp"
do
  port=${spec%:*}
  proto=${spec#*:}
  if [[ "$proto" == tcp ]]; then
    ss -H -lnt "sport = :$port" | grep -q .
  else
    ss -H -lnu "sport = :$port" | grep -q .
  fi
done

cat "$TMP/hbbs.log"
cat "$TMP/hbbr.log"
echo "RustDesk native custom-port smoke test passed."
