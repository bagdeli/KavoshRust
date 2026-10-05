#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="KavoshRust"
REPO_RAW="${KAVOSHRUST_REPO_RAW:-https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh}"
INSTALL_DIR="${KAVOSHRUST_INSTALL_DIR:-/opt/kavoshrust}"
ENV_FILE="$INSTALL_DIR/.env"
BIN_DIR="$INSTALL_DIR/bin"
DATA_DIR="$INSTALL_DIR/data"
VERSION_FILE="$INSTALL_DIR/version"
CLIENT_FILE="$INSTALL_DIR/client-config.txt"
BACKUP_DIR="${KAVOSHRUST_BACKUP_DIR:-/var/backups/kavoshrust}"
MANAGER_BIN="${KAVOSHRUST_MANAGER_BIN:-/usr/local/sbin/kavoshrust}"
LOG_FILE="${KAVOSHRUST_LOG_FILE:-/var/log/kavoshrust-manager.log}"
SYSTEMD_DIR="${KAVOSHRUST_SYSTEMD_DIR:-/etc/systemd/system}"
HBBS_UNIT="$SYSTEMD_DIR/kavoshrust-hbbs.service"
HBBR_UNIT="$SYSTEMD_DIR/kavoshrust-hbbr.service"
NGINX_SITE="${KAVOSHRUST_NGINX_SITE:-/etc/nginx/conf.d/kavoshrust.conf}"
ACME_WEBROOT="${KAVOSHRUST_ACME_WEBROOT:-/var/lib/kavoshrust-acme}"

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

is_installed(){
  [[ -f "$ENV_FILE" && -x "$BIN_DIR/hbbs" && -x "$BIN_DIR/hbbr" && -f "$HBBS_UNIT" && -f "$HBBR_UNIT" ]]
}

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
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

validate_host(){
  local h=${1,,}
  [[ "$h" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] ||
  [[ "$h" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

port_in_use(){
  local p=$1
  ss -H -lnt "sport = :$p" 2>/dev/null | grep -q . && return 0
  ss -H -lnu "sport = :$p" 2>/dev/null | grep -q . && return 0
  return 1
}

is_common_port(){
  local p=$1
  if [[ "$p" =~ ^[0-9]+$ ]] && (( p < 1024 )); then return 0; fi
  case "$p" in
    1433|1521|2049|2375|2376|3000|3306|3389|5432|5672|5900|6379|6443|8080|8443|9000|9090|9200|9300|27017) return 0;;
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
  local nat idws relws p
  nat=$((id-1)); idws=$((id+2)); relws=$((relay+2))

  validate_port_number "$id" || { fail "ID port must be between 1 and 65535."; return 1; }
  validate_port_number "$relay" || { fail "Relay port must be between 1 and 65535."; return 1; }
  (( nat >= 1 && idws <= 65535 && relws <= 65535 )) || {
    fail "Derived-port constraint: ID must be 2-65533 and Relay must be 1-65533."
    return 1
  }

  local ports=("$nat" "$id" "$idws" "$relay" "$relws")
  if [[ $(printf '%s\n' "${ports[@]}" | sort -n | uniq | wc -l) -ne ${#ports[@]} ]]; then
    fail "Selected RustDesk ports overlap."
    return 1
  fi

  for p in "${ports[@]}"; do
    if (( p >= 21115 && p <= 21119 )); then
      fail "Port layout touches RustDesk default range 21115-21119. Choose other ports."
      return 1
    fi
  done

  for p in "${ports[@]}"; do
    if [[ "$context" == change ]]; then
      port_allowed_for_change "$p" || { fail "Port $p is already used by another service."; return 1; }
    else
      ! port_in_use "$p" || { fail "Port $p is already in use."; return 1; }
    fi
  done
}

find_suggested_ports(){
  local id relay i
  for i in $(seq 1 400); do
    id=$(shuf -i 30000-50000 -n 1)
    relay=$(shuf -i 30000-50000 -n 1)
    validate_layout "$id" "$relay" install >/dev/null 2>&1 && {
      echo "$id $relay"
      return 0
    }
  done
  echo "45116 46117"
}

show_listeners(){
  echo -e "${CYAN}Current listening ports:${NC}"
  ss -tulpen 2>/dev/null | head -n 120 || true
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

routing_report(){
  local forwarding
  forwarding=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo unknown)
  echo -e "${CYAN}Routing safety:${NC}"
  echo "IPv4 forwarding: $forwarding"
  ip route show 2>/dev/null | head -n 40 || true
  ip rule show 2>/dev/null | head -n 40 || true
  info "KavoshRust uses native systemd services; Docker, bridge networking and Docker iptables are not installed."
}

install_dependencies(){
  info "Installing prerequisite packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl jq openssl tar gzip unzip iproute2 coreutils dnsutils
  ok "Prerequisites installed."
}

get_public_ip(){
  local ip=""
  ip=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
  [[ -n "$ip" ]] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "$ip"
}

resolve_domain_ipv4(){
  getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u
}

release_json(){
  curl -fsSL --retry 3 --connect-timeout 10 https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest
}

rustdesk_asset_arch(){
  case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
    amd64|x86_64) echo amd64;;
    arm64|aarch64) echo arm64v8;;
    armhf|armv7l) echo armv7;;
    i386|i686) echo i386;;
    *) fail "Unsupported CPU architecture."; return 1;;
  esac
}

install_rustdesk_binaries(){
  local json tag arch asset url digest tmp unpack hbbs_path hbbr_path
  json=$(release_json)
  tag=$(jq -r '.tag_name' <<<"$json")
  arch=$(rustdesk_asset_arch)
  asset="rustdesk-server-linux-$arch.zip"
  url=$(jq -r --arg n "$asset" '.assets[] | select(.name==$n) | .browser_download_url' <<<"$json" | head -n1)
  digest=$(jq -r --arg n "$asset" '.assets[] | select(.name==$n) | .digest // empty' <<<"$json" | head -n1)
  [[ -n "$tag" && -n "$url" && "$url" != null ]] || { fail "Could not resolve RustDesk release asset."; return 1; }

  tmp=$(mktemp)
  unpack=$(mktemp -d)
  info "Downloading RustDesk Server OSS $tag ($arch)..."
  curl -fL --retry 3 --connect-timeout 10 "$url" -o "$tmp"

  if [[ "$digest" == sha256:* ]]; then
    echo "${digest#sha256:}  $tmp" | sha256sum -c - >/dev/null || {
      rm -rf "$tmp" "$unpack"
      fail "RustDesk release checksum verification failed."
      return 1
    }
  fi

  unzip -q "$tmp" -d "$unpack"
  hbbs_path=$(find "$unpack" -type f -name hbbs -print -quit)
  hbbr_path=$(find "$unpack" -type f -name hbbr -print -quit)
  [[ -n "$hbbs_path" && -n "$hbbr_path" ]] || {
    rm -rf "$tmp" "$unpack"
    fail "Downloaded archive does not contain hbbs/hbbr."
    return 1
  }

  mkdir -p "$BIN_DIR"
  install -m 0755 "$hbbs_path" "$BIN_DIR/hbbs"
  install -m 0755 "$hbbr_path" "$BIN_DIR/hbbr"
  "$BIN_DIR/hbbs" --help >/dev/null
  "$BIN_DIR/hbbr" --help >/dev/null
  printf '%s\n' "$tag" >"$VERSION_FILE"
  rm -rf "$tmp" "$unpack"
  ok "RustDesk Server OSS $tag installed."
}

ensure_service_user(){
  mkdir -p "$DATA_DIR"
  if [[ "${KAVOSHRUST_TEST_MODE:-0}" == 1 ]]; then
    chmod 700 "$DATA_DIR"
    return 0
  fi
  if ! id kavoshrust >/dev/null 2>&1; then
    useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin kavoshrust
  fi
  chown -R kavoshrust:kavoshrust "$DATA_DIR"
  chmod 700 "$DATA_DIR"
}

write_env(){
  local domain=$1 id=$2 relay=$3 ssl=$4 web=$5 force_relay=$6 ssl_mode=${7:-none}
  umask 077
  cat >"$ENV_FILE" <<EOF
DOMAIN=$domain
ID_PORT=$id
RELAY_PORT=$relay
SSL_ENABLED=$ssl
SSL_MODE=$ssl_mode
WEB_PORTS_ENABLED=$web
ALWAYS_USE_RELAY=$force_relay
EOF
  chmod 600 "$ENV_FILE"
}

generate_systemd_units(){
  load_env
  ensure_service_user
  mkdir -p "$SYSTEMD_DIR"

  cat >"$HBBS_UNIT" <<EOF
[Unit]
Description=KavoshRust RustDesk ID/Rendezvous Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=kavoshrust
Group=kavoshrust
WorkingDirectory=$DATA_DIR
Environment=RUST_LOG=info
Environment=ALWAYS_USE_RELAY=${ALWAYS_USE_RELAY:-N}
ExecStart=$BIN_DIR/hbbs -p $ID_PORT -r $DOMAIN:$RELAY_PORT -k _
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  cat >"$HBBR_UNIT" <<EOF
[Unit]
Description=KavoshRust RustDesk Relay Server
After=network-online.target kavoshrust-hbbs.service
Wants=network-online.target

[Service]
Type=simple
User=kavoshrust
Group=kavoshrust
WorkingDirectory=$DATA_DIR
Environment=RUST_LOG=info
ExecStart=$BIN_DIR/hbbr -p $RELAY_PORT -k _
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  if [[ "${KAVOSHRUST_TEST_MODE:-0}" != 1 ]]; then
    systemctl daemon-reload
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

start_services(){
  is_installed || { fail "KavoshRust is not fully configured."; return 1; }
  load_env
  generate_systemd_units
  chown -R kavoshrust:kavoshrust "$DATA_DIR"
  systemctl enable --now kavoshrust-hbbs.service
  if ! wait_for_key; then
    journalctl -u kavoshrust-hbbs.service -n 80 --no-pager || true
    fail "hbbs did not generate/load the public key."
    return 1
  fi
  systemctl enable --now kavoshrust-hbbr.service
  systemctl is-active --quiet kavoshrust-hbbs.service
  systemctl is-active --quiet kavoshrust-hbbr.service
}

stop_services(){
  systemctl stop kavoshrust-hbbs.service kavoshrust-hbbr.service 2>/dev/null || true
}

restart_services(){
  systemctl restart kavoshrust-hbbs.service
  wait_for_key
  systemctl restart kavoshrust-hbbr.service
}

write_client_config(){
  load_env
  local key="(not generated)"
  [[ -s "$DATA_DIR/id_ed25519.pub" ]] && key=$(tr -d '\r\n' <"$DATA_DIR/id_ed25519.pub")
  cat >"$CLIENT_FILE" <<EOF
KavoshRust / RustDesk client settings
=====================================
ID Server:    $DOMAIN:$ID_PORT
Relay Server: $DOMAIN:$RELAY_PORT
API Server:   (leave empty for OSS)
Key:          $key

Use the same ID Server, Relay Server and Key on technician and customer clients.
For on-demand support, configure the customer client to require manual approval.
EOF
  chmod 600 "$CLIENT_FILE"
}

configure_firewall(){
  load_env
  local nat=$((ID_PORT-1)) idws=$((ID_PORT+2)) relws=$((RELAY_PORT+2))
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "$nat/tcp" comment 'KavoshRust NAT' >/dev/null
    ufw allow "$ID_PORT/tcp" comment 'KavoshRust ID TCP' >/dev/null
    ufw allow "$ID_PORT/udp" comment 'KavoshRust ID UDP' >/dev/null
    ufw allow "$RELAY_PORT/tcp" comment 'KavoshRust Relay' >/dev/null
    if [[ "${WEB_PORTS_ENABLED:-0}" == 1 ]]; then
      ufw allow "$idws/tcp" comment 'KavoshRust ID WS' >/dev/null
      ufw allow "$relws/tcp" comment 'KavoshRust Relay WS' >/dev/null
    fi
    ok "UFW rules applied; existing policy was not changed."
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$nat/tcp" >/dev/null
    firewall-cmd --permanent --add-port="$ID_PORT/tcp" >/dev/null
    firewall-cmd --permanent --add-port="$ID_PORT/udp" >/dev/null
    firewall-cmd --permanent --add-port="$RELAY_PORT/tcp" >/dev/null
    if [[ "${WEB_PORTS_ENABLED:-0}" == 1 ]]; then
      firewall-cmd --permanent --add-port="$idws/tcp" >/dev/null
      firewall-cmd --permanent --add-port="$relws/tcp" >/dev/null
    fi
    firewall-cmd --reload >/dev/null
    ok "firewalld rules applied."
  else
    warn "No active UFW/firewalld. KavoshRust will not enable a firewall."
    warn "Open the printed RustDesk ports in any provider-side firewall if one exists."
  fi
}

remove_firewall_rules(){
  local id=$1 relay=$2 web=${3:-0}
  local nat=$((id-1)) idws=$((id+2)) relws=$((relay+2))
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw delete allow "$nat/tcp" >/dev/null 2>&1 || true
    ufw delete allow "$id/tcp" >/dev/null 2>&1 || true
    ufw delete allow "$id/udp" >/dev/null 2>&1 || true
    ufw delete allow "$relay/tcp" >/dev/null 2>&1 || true
    if [[ "$web" == 1 ]]; then
      ufw delete allow "$idws/tcp" >/dev/null 2>&1 || true
      ufw delete allow "$relws/tcp" >/dev/null 2>&1 || true
    fi
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --remove-port="$nat/tcp" >/dev/null 2>&1 || true
    firewall-cmd --permanent --remove-port="$id/tcp" >/dev/null 2>&1 || true
    firewall-cmd --permanent --remove-port="$id/udp" >/dev/null 2>&1 || true
    firewall-cmd --permanent --remove-port="$relay/tcp" >/dev/null 2>&1 || true
    if [[ "$web" == 1 ]]; then
      firewall-cmd --permanent --remove-port="$idws/tcp" >/dev/null 2>&1 || true
      firewall-cmd --permanent --remove-port="$relws/tcp" >/dev/null 2>&1 || true
    fi
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}

nginx_owns_web_ports(){
  ss -H -lntp 'sport = :80' 2>/dev/null | grep -q nginx &&
  ss -H -lntp 'sport = :443' 2>/dev/null | grep -q nginx
}

domain_conflict_in_nginx(){
  local domain=$1
  [[ -d /etc/nginx ]] || return 1
  grep -R -F "$domain" /etc/nginx 2>/dev/null | grep -v -F "$NGINX_SITE" | grep -q .
}

write_nginx_http_site(){
  mkdir -p "$ACME_WEBROOT" "$(dirname "$NGINX_SITE")"
  cat >"$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_WEBROOT;
        default_type text/plain;
        try_files \$uri =404;
    }

    location = /health {
        default_type text/plain;
        return 200 "OK\n";
    }

    location / {
        return 404;
    }
}
EOF
}

write_nginx_https_site(){
  cat >"$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_WEBROOT;
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location = /health {
        default_type text/plain;
        return 200 "OK\n";
    }

    location / {
        default_type text/plain;
        return 200 "KavoshRust RustDesk server\n";
    }
}
EOF
}

safe_nginx_reload(){
  nginx -t || return 1
  systemctl reload nginx
}

ssl_precheck(){
  local domain=$1 public_ip resolved
  [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 1
  public_ip=$(get_public_ip)
  resolved=$(resolve_domain_ipv4 "$domain" | tr '\n' ' ')
  [[ -n "$public_ip" && -n "$resolved" && " $resolved " == *" $public_ip "* ]] || return 3
  nginx_owns_web_ports && return 0
  return 2
}

configure_nginx_ssl(){
  load_env
  local rc backup=""
  set +e; ssl_precheck "$DOMAIN"; rc=$?; set -e
  case "$rc" in
    0) ;;
    1) fail "SSL requires a DNS hostname, not an IP."; return 1;;
    2) fail "80/443 are not both owned by the existing Nginx. Refusing takeover."; return 1;;
    3) fail "DNS for $DOMAIN does not resolve to this server ($(get_public_ip))."; return 1;;
  esac

  if domain_conflict_in_nginx "$DOMAIN" && [[ ! -f "$NGINX_SITE" ]]; then
    fail "The domain appears in another Nginx config. Automatic takeover refused."
    return 1
  fi

  command -v certbot >/dev/null 2>&1 || {
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y certbot
  }

  mkdir -p "$ACME_WEBROOT" "$(dirname "$NGINX_SITE")"
  if [[ -f "$NGINX_SITE" ]]; then
    backup=$(mktemp)
    cp -a "$NGINX_SITE" "$backup"
  fi

  write_nginx_http_site
  if ! safe_nginx_reload; then
    [[ -n "$backup" ]] && cp -a "$backup" "$NGINX_SITE" || rm -f "$NGINX_SITE"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
    [[ -n "$backup" ]] && rm -f "$backup"
    fail "Nginx validation failed; KavoshRust change was rolled back."
    return 1
  fi

  if ! certbot certonly --webroot -w "$ACME_WEBROOT" -d "$DOMAIN" \
      --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring; then
    [[ -n "$backup" ]] && cp -a "$backup" "$NGINX_SITE" || rm -f "$NGINX_SITE"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
    [[ -n "$backup" ]] && rm -f "$backup"
    fail "Certificate issuance failed; Nginx was rolled back."
    return 1
  fi

  write_nginx_https_site
  if ! safe_nginx_reload; then
    [[ -n "$backup" ]] && cp -a "$backup" "$NGINX_SITE" || rm -f "$NGINX_SITE"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
    [[ -n "$backup" ]] && rm -f "$backup"
    fail "HTTPS Nginx validation failed; previous config restored."
    return 1
  fi
  [[ -n "$backup" ]] && rm -f "$backup"

  mkdir -p /etc/letsencrypt/renewal-hooks/deploy
  cat >/etc/letsencrypt/renewal-hooks/deploy/kavoshrust-nginx.sh <<'EOF'
#!/usr/bin/env bash
nginx -t && systemctl reload nginx
EOF
  chmod 755 /etc/letsencrypt/renewal-hooks/deploy/kavoshrust-nginx.sh
  systemctl enable --now certbot.timer >/dev/null 2>&1 || true

  sed -i 's/^SSL_ENABLED=.*/SSL_ENABLED=1/' "$ENV_FILE"
  sed -i 's/^SSL_MODE=.*/SSL_MODE=nginx/' "$ENV_FILE"
  cp -a "$NGINX_SITE" "$INSTALL_DIR/nginx-site.conf"
  ok "HTTPS enabled via existing Nginx; Certbot renewal is automatic."
}

disable_kavoshrust_ssl(){
  [[ -f "$NGINX_SITE" ]] && rm -f "$NGINX_SITE"
  if command -v nginx >/dev/null 2>&1; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi
  if [[ -f "$ENV_FILE" ]]; then
    sed -i 's/^SSL_ENABLED=.*/SSL_ENABLED=0/' "$ENV_FILE"
    sed -i 's/^SSL_MODE=.*/SSL_MODE=none/' "$ENV_FILE"
  fi
  ok "KavoshRust HTTPS vhost disabled; existing Nginx and certificate files were retained."
}

install_manager_command(){
  if curl -fsSL "$REPO_RAW" -o "$MANAGER_BIN"; then
    chmod 755 "$MANAGER_BIN"
    ok "Manager installed: kavoshrust"
  else
    warn "Could not install $MANAGER_BIN; current session still works."
  fi
}

install_server(){
  if is_installed; then
    warn "KavoshRust is already installed."
    if confirm "Repair/update the existing installation?" Y; then
      install_dependencies
      update_server
      show_server_info
    fi
    return
  fi

  check_os
  install_dependencies
  echo -e "${CYAN}Safety preflight: existing services will not be stopped or reconfigured.${NC}"
  show_listeners
  echo

  local domain suggested_id suggested_relay id relay rc web=0 force_relay=N
  read -r -p "Domain for RustDesk (example rust.kavosh.info): " domain
  domain=${domain,,}
  validate_host "$domain" || { fail "Invalid domain or IPv4."; return; }

  read -r suggested_id suggested_relay < <(find_suggested_ports)
  while true; do
    read -r -p "RustDesk ID port [$suggested_id]: " id
    id=${id:-$suggested_id}
    if is_common_port "$id"; then
      warn "ID port $id is privileged/common."
      confirm "Use it anyway?" N || continue
    fi

    read -r -p "RustDesk Relay port [$suggested_relay]: " relay
    relay=${relay:-$suggested_relay}
    if is_common_port "$relay"; then
      warn "Relay port $relay is privileged/common."
      confirm "Use it anyway?" N || continue
    fi

    echo "Listeners: NAT TCP=$((id-1)), ID TCP/UDP=$id, ID WS TCP=$((id+2)), Relay TCP=$relay, Relay WS TCP=$((relay+2))"
    validate_layout "$id" "$relay" install && break
  done

  mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DATA_DIR" "$BACKUP_DIR"
  chmod 700 "$INSTALL_DIR" "$DATA_DIR" "$BACKUP_DIR"
  write_env "$domain" "$id" "$relay" 0 "$web" "$force_relay" none

  install_rustdesk_binaries
  ensure_service_user
  generate_systemd_units
  configure_firewall
  start_services
  write_client_config
  install_manager_command

  set +e; ssl_precheck "$domain"; rc=$?; set -e
  case "$rc" in
    0)
      info "Existing Nginx and DNS are ready; configuring automatic SSL."
      configure_nginx_ssl || warn "RustDesk is running, but HTTPS setup failed. Use menu option 7 later."
      ;;
    1) warn "SSL skipped because an IP address was entered.";;
    2) warn "SSL skipped because 80/443 are not both owned by Nginx.";;
    3) warn "SSL skipped for now because DNS does not resolve to this server. Use menu option 7 after DNS is updated.";;
  esac

  show_server_info
}

show_server_info(){
  is_installed || { warn "Server is not installed."; return; }
  load_env
  local key="not generated" public_ip version="unknown"
  [[ -s "$DATA_DIR/id_ed25519.pub" ]] && key=$(tr -d '\r\n' <"$DATA_DIR/id_ed25519.pub")
  [[ -s "$VERSION_FILE" ]] && version=$(cat "$VERSION_FILE")
  public_ip=$(get_public_ip)

  echo -e "\n${CYAN}=== KavoshRust Server Information ===${NC}"
  printf 'Install mode:           native systemd\n'
  printf 'RustDesk version:       %s\n' "$version"
  printf 'Domain:                 %s\n' "$DOMAIN"
  printf 'Public IP:              %s\n' "${public_ip:-unknown}"
  printf 'ID Server:              %s:%s\n' "$DOMAIN" "$ID_PORT"
  printf 'Relay Server:           %s:%s\n' "$DOMAIN" "$RELAY_PORT"
  printf 'Public Key:             %s\n' "$key"
  printf 'NAT test TCP:           %s\n' "$((ID_PORT-1))"
  printf 'ID TCP/UDP:             %s\n' "$ID_PORT"
  printf 'ID WebSocket TCP:       %s (listener active; firewall default closed)\n' "$((ID_PORT+2))"
  printf 'Relay TCP:              %s\n' "$RELAY_PORT"
  printf 'Relay WebSocket TCP:    %s (listener active; firewall default closed)\n' "$((RELAY_PORT+2))"
  printf 'WebSocket firewall:     %s\n' "${WEB_PORTS_ENABLED:-0}"
  printf 'Force relay:            %s\n' "${ALWAYS_USE_RELAY:-N}"
  printf 'Automatic HTTPS:        %s (%s)\n' "${SSL_ENABLED:-0}" "${SSL_MODE:-none}"
  [[ "${SSL_ENABLED:-0}" == 1 ]] && printf 'Health URL:             https://%s/health\n' "$DOMAIN"
  echo
  cat "$CLIENT_FILE" 2>/dev/null || true
}

status_server(){
  is_installed || { warn "Not installed."; return; }
  load_env
  systemctl is-active --quiet kavoshrust-hbbs.service && ok "hbbs service active" || fail "hbbs service inactive" || true
  systemctl is-active --quiet kavoshrust-hbbr.service && ok "hbbr service active" || fail "hbbr service inactive" || true
  local p
  for p in "$((ID_PORT-1))" "$ID_PORT" "$((ID_PORT+2))" "$RELAY_PORT" "$((RELAY_PORT+2))"; do
    port_in_use "$p" && ok "Listener $p active" || fail "Expected listener $p missing" || true
  done
  if [[ "${SSL_ENABLED:-0}" == 1 ]]; then
    curl -fsS --max-time 8 "https://$DOMAIN/health" >/dev/null 2>&1 && ok "HTTPS health works" || warn "HTTPS health is not reachable"
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
  local old=$DOMAIN d
  read -r -p "New domain [$old]: " d
  d=${d:-$old}
  validate_host "$d" || { fail "Invalid domain."; return; }
  if [[ "${SSL_ENABLED:-0}" == 1 ]]; then disable_kavoshrust_ssl; fi
  sed -i "s|^DOMAIN=.*|DOMAIN=$d|" "$ENV_FILE"
  generate_systemd_units
  restart_services
  write_client_config
  warn "Domain changed. Update DNS and all clients, then enable SSL again from menu option 7."
  show_server_info
}

change_ports(){
  is_installed || { warn "Not installed."; return; }
  load_env
  local old_id=$ID_PORT old_relay=$RELAY_PORT old_web=${WEB_PORTS_ENABLED:-0} id relay
  echo "Current ID=$old_id Relay=$old_relay"
  while true; do
    read -r -p "New ID port [$old_id]: " id; id=${id:-$old_id}
    read -r -p "New Relay port [$old_relay]: " relay; relay=${relay:-$old_relay}
    echo "Listeners: $((id-1)), $id, $((id+2)), $relay, $((relay+2))"
    validate_layout "$id" "$relay" change && break
  done

  confirm "Apply and restart only KavoshRust services?" N || return
  stop_services
  remove_firewall_rules "$old_id" "$old_relay" "$old_web"
  sed -i "s/^ID_PORT=.*/ID_PORT=$id/" "$ENV_FILE"
  sed -i "s/^RELAY_PORT=.*/RELAY_PORT=$relay/" "$ENV_FILE"
  generate_systemd_units
  configure_firewall
  if ! start_services; then
    warn "New ports failed. Rolling back."
    sed -i "s/^ID_PORT=.*/ID_PORT=$old_id/" "$ENV_FILE"
    sed -i "s/^RELAY_PORT=.*/RELAY_PORT=$old_relay/" "$ENV_FILE"
    generate_systemd_units
    configure_firewall
    start_services || true
    return 1
  fi
  write_client_config
  ok "Ports changed. Update clients and provider-side firewall rules."
  show_server_info
}

ssl_manager(){
  is_installed || { warn "Not installed."; return; }
  load_env
  echo "SSL_ENABLED=${SSL_ENABLED:-0} | SSL_MODE=${SSL_MODE:-none} | Domain=$DOMAIN"
  echo "1) Enable/repair HTTPS with existing Nginx + Certbot"
  echo "2) Disable KavoshRust HTTPS vhost"
  echo "3) Certbot renewal dry-run"
  echo "0) Back"
  local c
  read -r -p "Select: " c
  case "$c" in
    1) configure_nginx_ssl;;
    2) disable_kavoshrust_ssl;;
    3) command -v certbot >/dev/null 2>&1 && certbot renew --dry-run || warn "Certbot is not installed.";;
    0) return;;
  esac
}

firewall_manager(){
  is_installed || { warn "Not installed."; return; }
  echo "KavoshRust only changes its exact port rules on an already-active UFW/firewalld."
  confirm "Apply/re-apply current KavoshRust rules?" Y && configure_firewall
}

toggle_web_ports(){
  is_installed || { warn "Not installed."; return; }
  load_env
  local idws=$((ID_PORT+2)) relws=$((RELAY_PORT+2))
  if [[ "${WEB_PORTS_ENABLED:-0}" == 1 ]]; then
    sed -i 's/^WEB_PORTS_ENABLED=.*/WEB_PORTS_ENABLED=0/' "$ENV_FILE"
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
      ufw delete allow "$idws/tcp" >/dev/null 2>&1 || true
      ufw delete allow "$relws/tcp" >/dev/null 2>&1 || true
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
      firewall-cmd --permanent --remove-port="$idws/tcp" >/dev/null 2>&1 || true
      firewall-cmd --permanent --remove-port="$relws/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    ok "WebSocket firewall ports closed. Native listeners remain local/host-bound as required by upstream."
  else
    sed -i 's/^WEB_PORTS_ENABLED=.*/WEB_PORTS_ENABLED=1/' "$ENV_FILE"
    configure_firewall
    ok "WebSocket firewall ports opened: $idws/TCP, $relws/TCP."
  fi
}

backup_server(){
  is_installed || { warn "Not installed."; return; }
  mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
  local out parent base
  out="$BACKUP_DIR/kavoshrust-$(date '+%Y%m%d-%H%M%S').tar.gz"
  parent=$(dirname "$INSTALL_DIR"); base=$(basename "$INSTALL_DIR")
  tar -C "$parent" -czf "$out" "$base"
  chmod 600 "$out"
  ok "Backup created: $out"
  warn "Backup contains the RustDesk private key."
}

restore_server(){
  local src parent base
  read -r -p "Full path to KavoshRust backup tar.gz: " src
  [[ -f "$src" ]] || { fail "Backup not found."; return; }
  parent=$(dirname "$INSTALL_DIR"); base=$(basename "$INSTALL_DIR")
  tar -tzf "$src" | grep -q "^$base/\\.env$" || { fail "Invalid backup: .env missing."; return; }
  tar -tzf "$src" | grep -q "^$base/data/" || { fail "Invalid backup: data directory missing."; return; }
  confirm "Restore replaces current KavoshRust config/data. Continue?" N || return

  is_installed && backup_server || true
  stop_services
  rm -rf "$INSTALL_DIR"
  mkdir -p "$parent"
  tar -C "$parent" -xzf "$src"
  ensure_service_user
  generate_systemd_units
  start_services
  write_client_config
  ok "Restore completed. Re-enable HTTPS from menu option 7 if needed."
}

update_server(){
  is_installed || { warn "Not installed."; return; }
  backup_server
  local rollback old_version
  rollback=$(mktemp -d)
  cp -a "$BIN_DIR/hbbs" "$BIN_DIR/hbbr" "$rollback/"
  old_version=$(cat "$VERSION_FILE" 2>/dev/null || echo unknown)

  if ! install_rustdesk_binaries; then
    rm -rf "$rollback"
    return 1
  fi

  if restart_services && systemctl is-active --quiet kavoshrust-hbbs.service && systemctl is-active --quiet kavoshrust-hbbr.service; then
    ok "RustDesk updated from $old_version to $(cat "$VERSION_FILE")."
    rm -rf "$rollback"
    return 0
  fi

  warn "Update failed; rolling back binaries."
  install -m 0755 "$rollback/hbbs" "$BIN_DIR/hbbs"
  install -m 0755 "$rollback/hbbr" "$BIN_DIR/hbbr"
  rm -rf "$rollback"
  restart_services || true
  fail "Update rolled back. Review logs."
}

force_relay_toggle(){
  is_installed || { warn "Not installed."; return; }
  load_env
  local new
  [[ "${ALWAYS_USE_RELAY:-N}" == Y ]] && new=N || new=Y
  sed -i "s/^ALWAYS_USE_RELAY=.*/ALWAYS_USE_RELAY=$new/" "$ENV_FILE"
  generate_systemd_units
  systemctl restart kavoshrust-hbbs.service
  ok "ALWAYS_USE_RELAY=$new"
}

preflight_report(){
  check_os
  echo -e "${CYAN}=== KavoshRust safe preflight (no changes) ===${NC}"
  local pretty
  pretty=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo unknown)
  echo "OS: $pretty"
  echo "Kernel: $(uname -r)"
  echo "CPU cores: $(nproc 2>/dev/null || echo unknown)"
  echo "Memory:"; free -h 2>/dev/null || true
  echo "Disk:"; df -h / 2>/dev/null || true
  echo "Nginx: $(nginx -v 2>&1 || echo not-installed)"
  echo "Public IPv4: $(get_public_ip)"
  echo
  routing_report
  echo
  scan_ports
  echo
  if nginx_owns_web_ports; then
    ok "80/443 are owned by existing Nginx; KavoshRust can add an isolated vhost after nginx -t validation."
  elif port_in_use 80 || port_in_use 443; then
    warn "80/443 are occupied but not both verified as Nginx. Automatic SSL will not take them over."
  else
    info "80/443 are free. Native RustDesk does not require them."
  fi
}

diagnostics(){
  is_installed || { warn "Not installed."; return; }
  load_env
  echo -e "${CYAN}=== System ===${NC}"
  uname -a
  echo "Uptime: $(uptime -p 2>/dev/null || true)"
  echo "Public IP: $(get_public_ip)"
  echo "DNS A records for $DOMAIN:"; resolve_domain_ipv4 "$DOMAIN" || true
  echo -e "\n${CYAN}=== RustDesk services ===${NC}"
  systemctl --no-pager --full status kavoshrust-hbbs.service kavoshrust-hbbr.service || true
  echo -e "\n${CYAN}=== Ports ===${NC}"
  status_server
  echo -e "\n${CYAN}=== hbbs logs ===${NC}"
  journalctl -u kavoshrust-hbbs.service -n 60 --no-pager || true
  echo -e "${CYAN}=== hbbr logs ===${NC}"
  journalctl -u kavoshrust-hbbr.service -n 60 --no-pager || true
  echo -e "${CYAN}=== Nginx validation ===${NC}"
  nginx -t 2>&1 || true
}

update_manager(){
  local tmp
  tmp=$(mktemp)
  curl -fsSL "$REPO_RAW" -o "$tmp"
  bash -n "$tmp"
  install -m 755 "$tmp" "$MANAGER_BIN"
  rm -f "$tmp"
  ok "Manager updated."
}

uninstall_server(){
  is_installed || { warn "Not installed."; return; }
  confirm "Stop and disable KavoshRust services?" N || return
  load_env
  stop_services
  systemctl disable kavoshrust-hbbs.service kavoshrust-hbbr.service >/dev/null 2>&1 || true
  remove_firewall_rules "$ID_PORT" "$RELAY_PORT" "${WEB_PORTS_ENABLED:-0}"
  rm -f "$HBBS_UNIT" "$HBBR_UNIT"
  systemctl daemon-reload

  [[ -f "$NGINX_SITE" ]] && disable_kavoshrust_ssl || true

  if confirm "DELETE RustDesk data, private key, binaries and config?" N; then
    rm -rf "$INSTALL_DIR"
    ok "KavoshRust data deleted."
  else
    ok "Services removed; data retained in $INSTALL_DIR."
  fi
  warn "Nginx, Certbot packages and certificate files were not removed."
}

show_logs(){
  is_installed || { warn "Not installed."; return; }
  echo "1) hbbs  2) hbbr  3) both"
  local c
  read -r -p "Select: " c
  case "$c" in
    1) journalctl -u kavoshrust-hbbs.service -n 200 -f;;
    2) journalctl -u kavoshrust-hbbr.service -n 200 -f;;
    3) journalctl -u kavoshrust-hbbs.service -u kavoshrust-hbbr.service -n 200 -f;;
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
      echo "Configured: $DOMAIN | ID:$ID_PORT | Relay:$RELAY_PORT | native"
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
 7) SSL / HTTPS manager (existing Nginx + Certbot)
 8) Firewall rules manager
 9) Restart RustDesk services
10) Start RustDesk services
11) Stop RustDesk services
12) View logs
13) Update RustDesk native binaries
14) Backup server
15) Restore backup
16) Toggle force-relay mode
17) Diagnostics
18) Update this manager script
19) Uninstall RustDesk service
20) Open/close WebSocket firewall ports
21) Safe preflight report
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
      9) is_installed && restart_services || warn "Not installed."; pause;;
      10) is_installed && start_services || warn "Not installed."; pause;;
      11) is_installed && stop_services || warn "Not installed."; pause;;
      12) show_logs; pause;;
      13) update_server; pause;;
      14) backup_server; pause;;
      15) restore_server; pause;;
      16) force_relay_toggle; pause;;
      17) diagnostics; pause;;
      18) update_manager; pause;;
      19) uninstall_server; pause;;
      20) toggle_web_ports; pause;;
      21) preflight_report; pause;;
      0) exit 0;;
      *) warn "Invalid option."; sleep 1;;
    esac
  done
}

if [[ "${KAVOSHRUST_LIB_ONLY:-0}" != 1 ]]; then
  require_root
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE" 2>/dev/null || true
  case "${1:-}" in
    --preflight) preflight_report; exit 0;;
    --status) status_server; exit 0;;
    --info) show_server_info; exit 0;;
    --diagnostics) diagnostics; exit 0;;
    --help)
      echo "Usage: kavoshrust [--preflight|--status|--info|--diagnostics]"
      echo "Without arguments, the interactive manager opens."
      exit 0
      ;;
  esac
  menu
fi
