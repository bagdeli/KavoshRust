#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="KavoshRust"
REPO_RAW="${KAVOSHRUST_REPO_RAW:-https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh}"
INSTALL_DIR="${KAVOSHRUST_INSTALL_DIR:-/opt/kavoshrust}"
ENV_FILE="$INSTALL_DIR/.env"
COMPOSE_FILE="$INSTALL_DIR/compose.yml"
CADDY_FILE="$INSTALL_DIR/Caddyfile"
WWW_DIR="$INSTALL_DIR/www"
DATA_DIR="$INSTALL_DIR/data"
BACKUP_DIR="${KAVOSHRUST_BACKUP_DIR:-/var/backups/kavoshrust}"
MANAGER_BIN="${KAVOSHRUST_MANAGER_BIN:-/usr/local/sbin/kavoshrust}"
LOG_FILE="${KAVOSHRUST_LOG_FILE:-/var/log/kavoshrust-manager.log}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

trap 'echo -e "${RED}[ERROR] line $LINENO: command failed.${NC}" >&2' ERR

log(){ printf '%s [%s] %s\n' "$(date '+%F %T')" "$PROJECT_NAME" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
info(){ echo -e "${BLUE}[INFO]${NC} $*"; log "INFO $*"; }
ok(){ echo -e "${GREEN}[OK]${NC} $*"; log "OK $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; log "WARN $*"; }
fail(){ echo -e "${RED}[FAIL]${NC} $*" >&2; log "FAIL $*"; return 1; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run as root: sudo bash <(curl -fsSL $REPO_RAW)" >&2
    exit 1
  fi
}

pause(){ read -r -p "Press Enter to continue..." _ || true; }
confirm(){
  local prompt="${1:-Continue?}" default="${2:-Y}" ans
  if [[ "$default" == Y ]]; then
    read -r -p "$prompt [Y/n]: " ans || true
    ans=${ans:-Y}
  else
    read -r -p "$prompt [y/N]: " ans || true
    ans=${ans:-N}
  fi
  [[ "$ans" =~ ^[Yy]$ ]]
}

is_installed(){ [[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]]; }

load_env(){
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

validate_port_number(){
  local p=$1
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1024 && p <= 65533 ))
}

port_in_use(){
  local p=$1
  ss -H -lnt "sport = :$p" 2>/dev/null | grep -q . && return 0
  ss -H -lnu "sport = :$p" 2>/dev/null | grep -q . && return 0
  return 1
}

is_common_port(){
  case "$1" in
    20|21|22|23|25|53|67|68|69|80|110|123|143|161|389|443|445|465|514|587|631|993|995|1433|1521|2049|2375|2376|3000|3306|3389|5432|5672|5900|6379|6443|8080|8443|9000|9090|9200|9300|27017) return 0;;
    *) return 1;;
  esac
}

current_rustdesk_ports(){
  if is_installed; then
    load_env
    printf '%s\n' "$((ID_PORT-1))" "$ID_PORT" "$((ID_PORT+2))" "$RELAY_PORT" "$((RELAY_PORT+2))"
  fi
}

port_allowed_for_change(){
  local p=$1
  if current_rustdesk_ports 2>/dev/null | grep -qx "$p"; then return 0; fi
  ! port_in_use "$p"
}

validate_layout(){
  local id=$1 relay=$2 context=${3:-install}
  local nat=$((id-1)) idws=$((id+2)) relws=$((relay+2)) p
  local ports=("$nat" "$id" "$idws" "$relay" "$relws")
  validate_port_number "$id" || { fail "ID port must be between 1024 and 65533."; return 1; }
  validate_port_number "$relay" || { fail "Relay port must be between 1024 and 65533."; return 1; }
  (( nat >= 1024 && idws <= 65535 && relws <= 65535 )) || { fail "Derived ports are outside the valid range."; return 1; }
  if [[ $(printf '%s\n' "${ports[@]}" | sort -n | uniq | wc -l) -ne 5 ]]; then
    fail "ID/Relay ports overlap with RustDesk derived ports."
    return 1
  fi
  for p in "${ports[@]}"; do
    if [[ "$context" == change ]]; then
      port_allowed_for_change "$p" || { fail "Port $p is already in use by another service."; return 1; }
    else
      ! port_in_use "$p" || { fail "Port $p is already in use."; return 1; }
    fi
  done
}

find_suggested_ports(){
  local id relay _
  for _ in $(seq 1 300); do
    id=$(shuf -i 30000-50000 -n 1)
    relay=$(shuf -i 30000-50000 -n 1)
    [[ "$id" == 21116 || "$relay" == 21117 ]] && continue
    if validate_layout "$id" "$relay" install >/dev/null 2>&1; then echo "$id $relay"; return 0; fi
  done
  echo "32116 33117"
}

show_listeners(){
  echo -e "${CYAN}Current listening ports (first 80):${NC}"
  ss -tulpen 2>/dev/null | head -n 81 || true
}

check_os(){
  [[ -r /etc/os-release ]] || { fail "Unsupported system."; exit 1; }
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) fail "Supported OS: Ubuntu/Debian. Detected: ${ID:-unknown}"; exit 1;;
  esac
}

install_dependencies(){
  info "Installing prerequisite packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl jq openssl tar gzip iproute2 coreutils dnsutils
  ok "Prerequisites installed."
}

install_docker(){
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker + Compose already available."
    systemctl enable --now docker >/dev/null 2>&1 || true
    return
  fi
  info "Installing Docker Engine from Docker's official installer..."
  local tmp
  tmp=$(mktemp)
  curl -fsSL https://get.docker.com -o "$tmp"
  sh "$tmp"
  rm -f "$tmp"
  systemctl enable --now docker
  docker compose version >/dev/null
  ok "Docker installed."
}

get_public_ip(){
  local ip=""
  ip=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
  [[ -n "$ip" ]] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "$ip"
}

resolve_domain_ipv4(){
  local d=$1
  getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | sort -u
}

write_env(){
  local domain=$1 id=$2 relay=$3 ssl=$4 web=$5 force_relay=$6
  umask 077
  cat >"$ENV_FILE" <<EOF
DOMAIN=$domain
ID_PORT=$id
RELAY_PORT=$relay
SSL_ENABLED=$ssl
WEB_PORTS_ENABLED=$web
ALWAYS_USE_RELAY=$force_relay
EOF
  chmod 600 "$ENV_FILE"
}

generate_caddy_files(){
  load_env
  mkdir -p "$WWW_DIR" "$INSTALL_DIR/caddy_data" "$INSTALL_DIR/caddy_config"
  cat >"$WWW_DIR/index.html" <<EOF
<!doctype html><html><head><meta charset="utf-8"><title>KavoshRust</title></head><body><h1>KavoshRust</h1><p>RustDesk server endpoint is online.</p></body></html>
EOF
  cat >"$CADDY_FILE" <<EOF
$DOMAIN {
    encode zstd gzip
    root * /srv
    file_server
    respond /health "OK" 200
}
EOF
}

generate_compose(){
  load_env
  cat >"$COMPOSE_FILE" <<'YAML'
services:
  hbbs:
    image: rustdesk/rustdesk-server:latest
    container_name: kavoshrust-hbbs
    command: hbbs -p ${ID_PORT} -r ${DOMAIN}:${RELAY_PORT}
    environment:
      RUST_LOG: info
      ALWAYS_USE_RELAY: ${ALWAYS_USE_RELAY}
    volumes:
      - ./data:/root
    network_mode: host
    restart: unless-stopped

  hbbr:
    image: rustdesk/rustdesk-server:latest
    container_name: kavoshrust-hbbr
    command: hbbr -p ${RELAY_PORT}
    environment:
      RUST_LOG: info
    volumes:
      - ./data:/root
    network_mode: host
    restart: unless-stopped
YAML
  if [[ "${SSL_ENABLED:-0}" == 1 ]]; then
    cat >>"$COMPOSE_FILE" <<'YAML'

  caddy:
    image: caddy:2
    container_name: kavoshrust-caddy
    ports:
      - "80:80/tcp"
      - "443:443/tcp"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./www:/srv:ro
      - ./caddy_data:/data
      - ./caddy_config:/config
    restart: unless-stopped
YAML
  fi
}

compose(){ (cd "$INSTALL_DIR" && docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"); }

configure_firewall(){
  load_env
  local nat=$((ID_PORT-1)) idws=$((ID_PORT+2)) relws=$((RELAY_PORT+2))
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    info "Active UFW detected; adding only KavoshRust rules."
    ufw allow "$nat/tcp" comment 'KavoshRust NAT' >/dev/null
    ufw allow "$ID_PORT/tcp" comment 'KavoshRust ID TCP' >/dev/null
    ufw allow "$ID_PORT/udp" comment 'KavoshRust ID UDP' >/dev/null
    ufw allow "$RELAY_PORT/tcp" comment 'KavoshRust Relay' >/dev/null
    if [[ "${WEB_PORTS_ENABLED:-0}" == 1 ]]; then
      ufw allow "$idws/tcp" comment 'KavoshRust ID WS' >/dev/null
      ufw allow "$relws/tcp" comment 'KavoshRust Relay WS' >/dev/null
    fi
    if [[ "${SSL_ENABLED:-0}" == 1 ]]; then
      ufw allow 80/tcp comment 'KavoshRust ACME HTTP' >/dev/null
      ufw allow 443/tcp comment 'KavoshRust HTTPS' >/dev/null
      ufw allow 443/udp comment 'KavoshRust HTTP3' >/dev/null || true
    fi
    ok "UFW rules applied without changing existing policy."
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    info "Active firewalld detected; adding only KavoshRust ports."
    firewall-cmd --permanent --add-port="$nat/tcp" >/dev/null
    firewall-cmd --permanent --add-port="$ID_PORT/tcp" >/dev/null
    firewall-cmd --permanent --add-port="$ID_PORT/udp" >/dev/null
    firewall-cmd --permanent --add-port="$RELAY_PORT/tcp" >/dev/null
    if [[ "${WEB_PORTS_ENABLED:-0}" == 1 ]]; then
      firewall-cmd --permanent --add-port="$idws/tcp" >/dev/null
      firewall-cmd --permanent --add-port="$relws/tcp" >/dev/null
    fi
    if [[ "${SSL_ENABLED:-0}" == 1 ]]; then
      firewall-cmd --permanent --add-service=http >/dev/null
      firewall-cmd --permanent --add-service=https >/dev/null
    fi
    firewall-cmd --reload >/dev/null
    ok "firewalld rules applied."
  else
    warn "No active UFW/firewalld detected. The script will NOT enable or replace your firewall."
    warn "Allow the printed RustDesk ports in your host/provider firewall."
  fi
}

wait_for_key(){
  local i
  for i in $(seq 1 30); do
    [[ -s "$DATA_DIR/id_ed25519.pub" ]] && return 0
    sleep 1
  done
  return 1
}

write_client_config(){
  load_env
  local key="(key not generated yet)"
  [[ -s "$DATA_DIR/id_ed25519.pub" ]] && key=$(tr -d '\r\n' <"$DATA_DIR/id_ed25519.pub")
  cat >"$INSTALL_DIR/client-config.txt" <<EOF
KavoshRust / RustDesk client settings
====================================
ID Server:    $DOMAIN:$ID_PORT
Relay Server: $DOMAIN:$RELAY_PORT
API Server:   (leave empty for OSS)
Key:          $key

Both support/operator and customer clients must use the same ID Server and Key.
Because Relay uses a non-default port, set Relay Server explicitly.
EOF
  chmod 600 "$INSTALL_DIR/client-config.txt"
}

ssl_precheck(){
  local domain=$1 public_ip resolved
  [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 1
  if port_in_use 80 || port_in_use 443; then return 2; fi
  public_ip=$(get_public_ip)
  resolved=$(resolve_domain_ipv4 "$domain" | tr '\n' ' ')
  if [[ -n "$public_ip" && -n "$resolved" && " $resolved " == *" $public_ip "* ]]; then return 0; fi
  return 3
}

install_manager_command(){
  if curl -fsSL "$REPO_RAW" -o "$MANAGER_BIN"; then
    chmod 755 "$MANAGER_BIN"
    ok "Manager installed: kavoshrust"
  else
    warn "Could not install $MANAGER_BIN; the current session still works."
  fi
}

install_server(){
  if is_installed; then
    warn "KavoshRust is already configured in $INSTALL_DIR."
    if confirm "Run repair/update instead?" Y; then
      install_dependencies
      install_docker
      generate_caddy_files
      generate_compose
      compose pull
      compose up -d
      wait_for_key || true
      write_client_config
      show_server_info
    fi
    return
  fi
  check_os
  install_dependencies
  echo -e "${CYAN}Safety preflight:${NC} existing services are never stopped or reconfigured."
  show_listeners
  echo

  local domain suggested_id suggested_relay id relay ssl=1 web=0 force_relay=N rc
  read -r -p "Domain for this RustDesk server (example rust.kavosh.info): " domain
  domain=${domain,,}
  [[ -n "$domain" && "$domain" != *" "* ]] || { fail "A valid domain or public IPv4 is required."; return; }

  read -r suggested_id suggested_relay < <(find_suggested_ports)
  while true; do
    read -r -p "RustDesk ID port [$suggested_id]: " id
    id=${id:-$suggested_id}
    if is_common_port "$id"; then
      warn "Port $id is a common service port."
      confirm "Use it anyway?" N || continue
    fi
    read -r -p "RustDesk Relay port [$suggested_relay]: " relay
    relay=${relay:-$suggested_relay}
    if is_common_port "$relay"; then
      warn "Port $relay is a common service port."
      confirm "Use it anyway?" N || continue
    fi
    echo "RustDesk will bind: NAT TCP=$((id-1)), ID TCP/UDP=$id, ID WS TCP=$((id+2)), Relay TCP=$relay, Relay WS TCP=$((relay+2))."
    validate_layout "$id" "$relay" install && break
  done

  if [[ "$id" == 21116 || "$relay" == 21117 ]]; then
    warn "Default RustDesk ports selected."
    confirm "Continue with defaults?" N || return
  fi

  set +e
  ssl_precheck "$domain"; rc=$?
  set -e
  case "$rc" in
    0) ssl=1; info "80/443 are free and DNS points here; automatic HTTPS enabled.";;
    1) ssl=0; warn "IP entered; public SSL needs a DNS name. SSL skipped.";;
    2) ssl=0; warn "80 or 443 is busy. To avoid disruption, bundled Caddy/SSL will NOT start.";;
    3) ssl=1; warn "DNS does not yet point here. Caddy will retry certificate issuance automatically after DNS is corrected.";;
  esac

  install_docker
  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$BACKUP_DIR"
  chmod 700 "$INSTALL_DIR" "$DATA_DIR" "$BACKUP_DIR"
  write_env "$domain" "$id" "$relay" "$ssl" "$web" "$force_relay"
  generate_caddy_files
  generate_compose
  configure_firewall
  info "Pulling RustDesk Server OSS containers..."
  compose pull
  compose up -d
  if wait_for_key; then ok "RustDesk server key generated."; else warn "Key is not visible yet; check logs."; fi
  write_client_config
  install_manager_command
  sleep 2
  show_server_info
}

show_server_info(){
  is_installed || { warn "Server is not installed yet."; return; }
  load_env
  local key="not generated" public_ip
  [[ -s "$DATA_DIR/id_ed25519.pub" ]] && key=$(tr -d '\r\n' <"$DATA_DIR/id_ed25519.pub")
  public_ip=$(get_public_ip)
  echo -e "\n${CYAN}=== KavoshRust Server Information ===${NC}"
  printf 'Domain:                %s\n' "$DOMAIN"
  printf 'Public IP:             %s\n' "${public_ip:-unknown}"
  printf 'ID Server:             %s:%s\n' "$DOMAIN" "$ID_PORT"
  printf 'Relay Server:          %s:%s\n' "$DOMAIN" "$RELAY_PORT"
  printf 'Public Key:            %s\n' "$key"
  printf 'NAT test TCP:          %s\n' "$((ID_PORT-1))"
  printf 'ID TCP/UDP:            %s\n' "$ID_PORT"
  printf 'ID WebSocket TCP:      %s\n' "$((ID_PORT+2))"
  printf 'Relay TCP:             %s\n' "$RELAY_PORT"
  printf 'Relay WebSocket TCP:   %s\n' "$((RELAY_PORT+2))"
  printf 'Force relay:           %s\n' "${ALWAYS_USE_RELAY:-N}"
  printf 'Automatic HTTPS:       %s\n' "${SSL_ENABLED:-0}"
  [[ "${SSL_ENABLED:-0}" == 1 ]] && printf 'Health URL:            https://%s/health\n' "$DOMAIN"
  echo
  compose ps || true
  echo -e "${CYAN}Client configuration:${NC}"
  cat "$INSTALL_DIR/client-config.txt" 2>/dev/null || true
}

status_server(){
  is_installed || { warn "Not installed."; return; }
  load_env
  compose ps || true
  echo
  local p
  for p in "$((ID_PORT-1))" "$ID_PORT" "$((ID_PORT+2))" "$RELAY_PORT" "$((RELAY_PORT+2))"; do
    if port_in_use "$p"; then ok "Port $p is listening"; else fail "Port $p is NOT listening" || true; fi
  done
  if [[ "${SSL_ENABLED:-0}" == 1 ]]; then
    curl -fsS --max-time 8 "https://$DOMAIN/health" >/dev/null 2>&1 && ok "HTTPS health endpoint works" || warn "HTTPS health endpoint is not ready/reachable"
  fi
}

scan_ports(){
  echo -e "${CYAN}Important/common ports:${NC}"
  local ports=(22 25 53 80 443 3306 5432 6379 8080 8443 21114 21115 21116 21117 21118 21119) p state
  for p in "${ports[@]}"; do
    if port_in_use "$p"; then state=BUSY; else state=free; fi
    printf '%-6s %s\n' "$p" "$state"
  done
  echo
  show_listeners
}

change_domain(){
  is_installed || { warn "Not installed."; return; }
  load_env
  local d old=$DOMAIN
  read -r -p "New domain [$old]: " d
  d=${d:-$old}
  [[ -n "$d" && "$d" != *" "* ]] || { fail "Invalid domain."; return; }
  sed -i "s|^DOMAIN=.*|DOMAIN=$d|" "$ENV_FILE"
  generate_caddy_files
  generate_compose
  compose up -d
  load_env
  if [[ "${SSL_ENABLED:-0}" == 1 ]]; then
    compose restart caddy || true
  fi
  write_client_config
  ok "Domain updated. Ensure DNS points to this server and update all clients."
  show_server_info
}

change_ports(){
  is_installed || { warn "Not installed."; return; }
  load_env
  local old_id=$ID_PORT old_relay=$RELAY_PORT id relay
  echo "Current ID=$old_id Relay=$old_relay"
  while true; do
    read -r -p "New ID port [$old_id]: " id; id=${id:-$old_id}
    read -r -p "New Relay port [$old_relay]: " relay; relay=${relay:-$old_relay}
    echo "Derived: $((id-1)), $id, $((id+2)), $relay, $((relay+2))"
    validate_layout "$id" "$relay" change && break
  done
  confirm "Apply and restart only RustDesk containers?" N || return
  compose stop hbbs hbbr || true
  sed -i "s/^ID_PORT=.*/ID_PORT=$id/" "$ENV_FILE"
  sed -i "s/^RELAY_PORT=.*/RELAY_PORT=$relay/" "$ENV_FILE"
  configure_firewall
  compose up -d hbbs hbbr
  wait_for_key || true
  write_client_config
  ok "Ports updated. Update ALL RustDesk clients and provider firewall rules."
  show_server_info
}

ssl_manager(){
  is_installed || { warn "Not installed."; return; }
  load_env
  echo "SSL_ENABLED=${SSL_ENABLED:-0} | Domain=$DOMAIN"
  echo "1) Enable/repair automatic HTTPS"
  echo "2) Disable bundled Caddy HTTPS"
  echo "3) Show Caddy logs"
  echo "0) Back"
  local c rc
  read -r -p "Select: " c
  case "$c" in
    1)
      if [[ "${SSL_ENABLED:-0}" != 1 ]] && { port_in_use 80 || port_in_use 443; }; then
        fail "80/443 is in use. Caddy will not start because that could disrupt another service."; return
      fi
      set +e; ssl_precheck "$DOMAIN"; rc=$?; set -e
      [[ "$rc" == 1 ]] && { fail "SSL needs a DNS name, not an IP."; return; }
      sed -i 's/^SSL_ENABLED=.*/SSL_ENABLED=1/' "$ENV_FILE"
      generate_caddy_files
      generate_compose
      configure_firewall
      compose up -d
      ok "Caddy enabled; certificate issuance/renewal is automatic."
      ;;
    2)
      docker rm -f kavoshrust-caddy >/dev/null 2>&1 || true
      sed -i 's/^SSL_ENABLED=.*/SSL_ENABLED=0/' "$ENV_FILE"
      generate_compose
      ok "Bundled Caddy disabled."
      ;;
    3) docker logs --tail 150 kavoshrust-caddy 2>&1 || true;;
    0) return;;
  esac
}

firewall_manager(){
  is_installed || { warn "Not installed."; return; }
  echo "This only ADDS KavoshRust rules to an already-active UFW/firewalld; it never enables a firewall or changes default policy."
  confirm "Apply/re-apply safe RustDesk rules?" Y && configure_firewall
}

backup_server(){
  is_installed || { warn "Not installed."; return; }
  mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
  local out="$BACKUP_DIR/kavoshrust-$(date '+%Y%m%d-%H%M%S').tar.gz"
  tar -C /opt -czf "$out" kavoshrust
  chmod 600 "$out"
  ok "Backup created: $out"
  warn "Backup contains the RustDesk private key; protect this file."
}

restore_server(){
  local src
  read -r -p "Full path to KavoshRust backup tar.gz: " src
  [[ -f "$src" ]] || { fail "Backup not found."; return; }
  confirm "Restore will replace current KavoshRust config/data. Continue?" N || return
  if is_installed; then compose down || true; backup_server; fi
  rm -rf "$INSTALL_DIR"
  tar -C /opt -xzf "$src"
  [[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]] || { fail "Invalid backup."; return; }
  compose up -d
  write_client_config
  ok "Restore completed."
}

update_server(){
  is_installed || { warn "Not installed."; return; }
  compose pull
  compose up -d
  ok "RustDesk containers updated."
}

force_relay_toggle(){
  is_installed || { warn "Not installed."; return; }
  load_env
  local new
  if [[ "${ALWAYS_USE_RELAY:-N}" == Y ]]; then new=N; else new=Y; fi
  sed -i "s/^ALWAYS_USE_RELAY=.*/ALWAYS_USE_RELAY=$new/" "$ENV_FILE"
  compose up -d --force-recreate hbbs
  ok "ALWAYS_USE_RELAY=$new"
}

diagnostics(){
  is_installed || { warn "Not installed."; return; }
  load_env
  echo -e "${CYAN}=== System ===${NC}"
  uname -a
  echo "Uptime: $(uptime -p 2>/dev/null || true)"
  echo "Public IP: $(get_public_ip)"
  echo "DNS A records for $DOMAIN:"
  resolve_domain_ipv4 "$DOMAIN" || true
  echo -e "\n${CYAN}=== Docker ===${NC}"
  docker --version || true
  docker compose version || true
  compose ps || true
  echo -e "\n${CYAN}=== Ports ===${NC}"
  status_server
  echo -e "\n${CYAN}=== Recent hbbs logs ===${NC}"
  docker logs --tail 40 kavoshrust-hbbs 2>&1 || true
  echo -e "${CYAN}=== Recent hbbr logs ===${NC}"
  docker logs --tail 40 kavoshrust-hbbr 2>&1 || true
}

update_manager(){
  local tmp
  tmp=$(mktemp)
  curl -fsSL "$REPO_RAW" -o "$tmp"
  bash -n "$tmp"
  install -m 755 "$tmp" "$MANAGER_BIN"
  rm -f "$tmp"
  ok "Manager updated: $MANAGER_BIN"
}

uninstall_server(){
  is_installed || { warn "Not installed."; return; }
  confirm "Stop and remove KavoshRust containers?" N || return
  compose down || true
  if confirm "DELETE all RustDesk data, keys, configs and local Caddy certificates?" N; then
    rm -rf "$INSTALL_DIR"
    ok "KavoshRust data deleted."
  else
    ok "Containers removed; data retained in $INSTALL_DIR."
  fi
  warn "Docker itself and existing firewall rules were intentionally left untouched."
}

show_logs(){
  is_installed || { warn "Not installed."; return; }
  echo "1) hbbs  2) hbbr  3) caddy  4) all RustDesk"
  local c
  read -r -p "Select: " c
  case "$c" in
    1) docker logs --tail 200 -f kavoshrust-hbbs || true;;
    2) docker logs --tail 200 -f kavoshrust-hbbr || true;;
    3) docker logs --tail 200 -f kavoshrust-caddy || true;;
    4) compose logs --tail 200 -f hbbs hbbr || true;;
  esac
}

banner(){
  clear 2>/dev/null || true
  echo -e "${CYAN}====================================================${NC}"
  echo -e "${CYAN}        KavoshRust - RustDesk OSS Manager           ${NC}"
  echo -e "${CYAN}====================================================${NC}"
}

menu(){
  while true; do
    banner
    if is_installed; then
      load_env
      echo "Configured: $DOMAIN | ID:$ID_PORT | Relay:$RELAY_PORT"
    else
      echo "Status: not installed"
    fi
    echo
    cat <<'MENU'
 1) Install / Repair RustDesk OSS
 2) Status
 3) Show server + client connection info
 4) Scan/list occupied ports
 5) Change domain
 6) Change RustDesk ports
 7) SSL / HTTPS manager
 8) Firewall rules manager
 9) Restart services
10) Start services
11) Stop services
12) View logs
13) Update RustDesk containers
14) Backup server
15) Restore backup
16) Toggle force-relay mode
17) Diagnostics
18) Update this manager script
19) Uninstall RustDesk service
 0) Exit
MENU
    local choice
    read -r -p "Select an option: " choice
    case "$choice" in
      1) install_server; pause;;
      2) status_server; pause;;
      3) show_server_info; pause;;
      4) scan_ports; pause;;
      5) change_domain; pause;;
      6) change_ports; pause;;
      7) ssl_manager; pause;;
      8) firewall_manager; pause;;
      9) is_installed && compose restart || warn "Not installed."; pause;;
      10) is_installed && compose up -d || warn "Not installed."; pause;;
      11) is_installed && compose stop || warn "Not installed."; pause;;
      12) show_logs; pause;;
      13) update_server; pause;;
      14) backup_server; pause;;
      15) restore_server; pause;;
      16) force_relay_toggle; pause;;
      17) diagnostics; pause;;
      18) update_manager; pause;;
      19) uninstall_server; pause;;
      0) exit 0;;
      *) warn "Invalid option."; sleep 1;;
    esac
  done
}

if [[ "${KAVOSHRUST_LIB_ONLY:-0}" != 1 ]]; then
  require_root
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE" 2>/dev/null || true
  menu
fi
