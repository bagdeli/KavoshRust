#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export KAVOSHRUST_LIB_ONLY=1
export KAVOSHRUST_INSTALL_DIR="$(mktemp -d)"
export KAVOSHRUST_BACKUP_DIR="$KAVOSHRUST_INSTALL_DIR/backups"
export KAVOSHRUST_MANAGER_BIN="$KAVOSHRUST_INSTALL_DIR/kavoshrust"
export KAVOSHRUST_LOG_FILE="$KAVOSHRUST_INSTALL_DIR/test.log"
trap 'rm -rf "$KAVOSHRUST_INSTALL_DIR"' EXIT

# shellcheck source=install.sh
source "$ROOT_DIR/install.sh"

pass=0
fail_count=0

check() {
  local name=$1
  shift
  if "$@"; then
    echo "PASS: $name"
    pass=$((pass+1))
  else
    echo "FAIL: $name"
    fail_count=$((fail_count+1))
  fi
}

check "valid high port" validate_port_number 32116
check "valid domain" validate_host rust.example.com
check "valid IPv4" validate_host 203.0.113.10
if validate_host 'bad host;rm'; then echo "FAIL: unsafe hostname rejected"; fail_count=$((fail_count+1)); else echo "PASS: unsafe hostname rejected"; pass=$((pass+1)); fi
if validate_port_number 80; then echo "FAIL: privileged port rejected"; fail_count=$((fail_count+1)); else echo "PASS: privileged port rejected"; pass=$((pass+1)); fi
if validate_port_number 70000; then echo "FAIL: >65535 rejected"; fail_count=$((fail_count+1)); else echo "PASS: >65535 rejected"; pass=$((pass+1)); fi

port_in_use() { return 1; }
current_rustdesk_ports() { return 1; }

check "valid independent ID/relay layout" validate_layout 32116 33117 install
if validate_layout 32116 32118 install >/dev/null 2>&1; then
  echo "FAIL: overlap should be rejected"; fail_count=$((fail_count+1))
else
  echo "PASS: overlap rejected"; pass=$((pass+1))
fi

mkdir -p "$KAVOSHRUST_INSTALL_DIR/data"
write_env "rust.example.com" 32116 33117 1 0 N
generate_caddy_files
generate_compose

grep -q 'command: \["hbbs", "-p", "32116", "-r", "rust.example.com:33117"\]' "$COMPOSE_FILE" && { echo "PASS: hbbs custom-port compose"; pass=$((pass+1)); } || { echo "FAIL: hbbs custom-port compose"; fail_count=$((fail_count+1)); }
grep -q 'command: \["hbbr", "-p", "33117"\]' "$COMPOSE_FILE" && { echo "PASS: hbbr custom-port compose"; pass=$((pass+1)); } || { echo "FAIL: hbbr custom-port compose"; fail_count=$((fail_count+1)); }
grep -q '"32115:32115/tcp"' "$COMPOSE_FILE" && { echo "PASS: NAT port published"; pass=$((pass+1)); } || { echo "FAIL: NAT port published"; fail_count=$((fail_count+1)); }
grep -q '"32116:32116/udp"' "$COMPOSE_FILE" && { echo "PASS: ID UDP published"; pass=$((pass+1)); } || { echo "FAIL: ID UDP published"; fail_count=$((fail_count+1)); }
if grep -q '"32118:32118/tcp"' "$COMPOSE_FILE"; then echo "FAIL: WebSocket should be unpublished by default"; fail_count=$((fail_count+1)); else echo "PASS: WebSocket unpublished by default"; pass=$((pass+1)); fi
grep -q 'caddy:' "$COMPOSE_FILE" && { echo "PASS: SSL service generated"; pass=$((pass+1)); } || { echo "FAIL: SSL service generated"; fail_count=$((fail_count+1)); }
grep -q 'rust.example.com' "$CADDY_FILE" && { echo "PASS: domain in Caddyfile"; pass=$((pass+1)); } || { echo "FAIL: domain in Caddyfile"; fail_count=$((fail_count+1)); }

echo "Tests: $pass passed, $fail_count failed"
[[ $fail_count -eq 0 ]]
