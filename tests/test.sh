#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export KAVOSHRUST_LIB_ONLY=1
export KAVOSHRUST_TEST_MODE=1
export KAVOSHRUST_INSTALL_DIR="$TMP/opt/kavoshrust"
export KAVOSHRUST_BACKUP_DIR="$TMP/backups"
export KAVOSHRUST_MANAGER_BIN="$TMP/kavoshrust"
export KAVOSHRUST_LOG_FILE="$TMP/manager.log"
export KAVOSHRUST_SYSTEMD_DIR="$TMP/systemd"
export KAVOSHRUST_NGINX_SITE="$TMP/nginx/kavoshrust.conf"
export KAVOSHRUST_ACME_WEBROOT="$TMP/acme"

# shellcheck source=../install.sh
source "$ROOT/install.sh"

fail_test(){ echo "FAIL: $*" >&2; exit 1; }

validate_port_number 1 || fail_test "port 1 rejected"
validate_port_number 80 || fail_test "privileged port 80 rejected"
validate_port_number 45116 || fail_test "high port rejected"
validate_port_number 65535 || fail_test "port 65535 rejected"
if validate_port_number 0; then fail_test "port 0 accepted"; fi
if validate_port_number 65536; then fail_test "port 65536 accepted"; fi

validate_host rust.kavosh.info || fail_test "valid domain rejected"
if validate_host 'bad_domain'; then fail_test "invalid domain accepted"; fi

is_common_port 22 || fail_test "SSH port not marked common"
is_common_port 80 || fail_test "HTTP port not marked common"
if is_common_port 45116; then fail_test "high port incorrectly marked common"; fi

validate_layout 45116 46117 install || fail_test "valid native custom layout rejected"

if validate_layout 1 46117 install >/dev/null 2>&1; then
  fail_test "ID=1 accepted even though ID-1 is invalid"
fi

if validate_layout 65534 46117 install >/dev/null 2>&1; then
  fail_test "ID=65534 accepted even though ID+2 is invalid"
fi

if validate_layout 21116 46117 install >/dev/null 2>&1; then
  fail_test "RustDesk default port layout accepted"
fi

if validate_layout 45116 45118 install >/dev/null 2>&1; then
  fail_test "overlapping ID WS/Relay layout accepted"
fi

mkdir -p "$KAVOSHRUST_INSTALL_DIR"
write_env rust.example.com 45116 46117 0 0 N none
generate_systemd_units

grep -Fq "ExecStart=$BIN_DIR/hbbs -p 45116 -r rust.example.com:46117 -k _" "$HBBS_UNIT" ||
  fail_test "hbbs systemd command incorrect"
grep -Fq "ExecStart=$BIN_DIR/hbbr -p 46117 -k _" "$HBBR_UNIT" ||
  fail_test "hbbr systemd command incorrect"
grep -Fq "AmbientCapabilities=CAP_NET_BIND_SERVICE" "$HBBS_UNIT" ||
  fail_test "low-port capability missing"

DOMAIN=rust.example.com
write_nginx_http_site
grep -Fq "server_name rust.example.com;" "$NGINX_SITE" || fail_test "nginx server_name missing"
grep -Fq "location ^~ /.well-known/acme-challenge/" "$NGINX_SITE" || fail_test "ACME location missing"

bash -n "$ROOT/install.sh"

echo "All KavoshRust native unit tests passed."
