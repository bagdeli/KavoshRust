#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export KAVOSHRUST_LIB_ONLY=1
export KAVOSHRUST_INSTALL_DIR="$TMP/opt/kavoshrust"
export KAVOSHRUST_BACKUP_DIR="$TMP/backups"
export KAVOSHRUST_MANAGER_BIN="$TMP/kavoshrust"
export KAVOSHRUST_LOG_FILE="$TMP/manager.log"

# shellcheck source=../install.sh
source "$ROOT/install.sh"

fail_test(){ echo "FAIL: $*" >&2; exit 1; }

validate_port_number 45116 || fail_test "high port rejected"
if validate_port_number 80; then fail_test "privileged port accepted"; fi

validate_host rust.kavosh.info || fail_test "valid domain rejected"
if validate_host 'bad_domain'; then fail_test "invalid domain accepted"; fi

is_common_port 22 || fail_test "common SSH port not detected"
if is_common_port 45116; then fail_test "high test port marked common"; fi

validate_layout 45116 46117 install 0 || fail_test "valid custom native layout rejected"

if validate_layout 21116 22117 install 0 >/dev/null 2>&1; then
  fail_test "layout touching RustDesk default ports was accepted"
fi

if validate_layout 45116 45118 install 1 >/dev/null 2>&1; then
  fail_test "overlapping ID WebSocket/Relay layout was accepted"
fi

mkdir -p "$KAVOSHRUST_INSTALL_DIR"
write_env rust.example.com 45116 46117 0 0 N
generate_compose

grep -Fq 'command: ["hbbs", "-p", "45116", "-r", "rust.example.com:46117", "-k", "_"]' "$COMPOSE_FILE" ||
  fail_test "hbbs command/relay/key validation missing"
grep -Fq 'command: ["hbbr", "-p", "46117", "-k", "_"]' "$COMPOSE_FILE" ||
  fail_test "hbbr key validation missing"
grep -Fq '"45115:45115/tcp"' "$COMPOSE_FILE" || fail_test "NAT port mapping missing"
grep -Fq '"45116:45116/tcp"' "$COMPOSE_FILE" || fail_test "ID TCP mapping missing"
grep -Fq '"45116:45116/udp"' "$COMPOSE_FILE" || fail_test "ID UDP mapping missing"
grep -Fq '"46117:46117/tcp"' "$COMPOSE_FILE" || fail_test "Relay mapping missing"

if grep -Fq '"45118:45118/tcp"' "$COMPOSE_FILE"; then
  fail_test "ID WebSocket exposed while disabled"
fi
if grep -Fq '"46119:46119/tcp"' "$COMPOSE_FILE"; then
  fail_test "Relay WebSocket exposed while disabled"
fi

write_env rust.example.com 45116 46117 0 1 Y
generate_compose
grep -Fq '"45118:45118/tcp"' "$COMPOSE_FILE" || fail_test "ID WebSocket missing when enabled"
grep -Fq '"46119:46119/tcp"' "$COMPOSE_FILE" || fail_test "Relay WebSocket missing when enabled"
grep -Fq 'ALWAYS_USE_RELAY: "Y"' "$COMPOSE_FILE" || fail_test "force-relay environment missing"

bash -n "$ROOT/install.sh"

echo "All KavoshRust tests passed."
