# Kavosh production deployment

Target server observed during preflight:

```text
Ubuntu 24.04 LTS
Public IPv4: 95.182.115.117
Existing services: nginx, sing-box, unbound and Kavosh application services
TCP 80/443: owned by nginx
Docker: not installed
IPv4 forwarding: 0
```

The intended RustDesk hostname is:

```text
rust.kavosh.info
```

## 1. DNS first

Create/update the A record:

```text
rust.kavosh.info -> 95.182.115.117
```

Do not request the certificate until public DNS resolves to that address.

## 2. Run preflight again

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh) --preflight
```

This is read-only.

## 3. Installation design for this host

KavoshRust uses **native RustDesk binaries + systemd** on this server.

It does not install Docker, create a Docker bridge or add Docker iptables rules.

Existing Nginx remains the owner of ports 80 and 443.

## 4. Choose ports

The installer proposes random high ports. You may also choose your own.

A reasonable example is:

```text
ID Port:    45116
Relay Port: 46117
```

This implies:

```text
45115/TCP  NAT test
45116/TCP  ID/rendezvous
45116/UDP  heartbeat/hole punching
45118/TCP  hbbs WebSocket listener

46117/TCP  relay
46119/TCP  hbbr WebSocket listener
```

The actual installer checks every one of those ports before writing systemd units. If any is occupied, choose another pair.

The default RustDesk range `21115-21119` is intentionally rejected.

## 5. Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh)
```

Choose:

```text
1) Install / Repair RustDesk OSS
```

Enter `rust.kavosh.info` when asked for the domain.

## 6. Automatic SSL

When DNS points to the server, KavoshRust detects that Nginx already owns 80/443.

It adds an isolated KavoshRust vhost, validates with `nginx -t`, reloads Nginx, gets a certificate using Certbot webroot mode, then validates/reloads Nginx again.

It does not replace the existing Nginx configuration.

The HTTPS endpoint is for health/domain validation and future integrations; native RustDesk uses the selected RustDesk ports.

## 7. Verify

```bash
kavoshrust --status
kavoshrust --info
kavoshrust --diagnostics
```

## 8. Configure clients

Copy the exact ID Server, Relay Server and public Key printed by:

```bash
kavoshrust --info
```

Use those values on both support-operator and customer clients.

For on-demand support, configure the controlled/customer client to require manual approval.

## 9. Firewall

KavoshRust does not enable a host firewall. If UFW/firewalld is already active, it only manages the RustDesk rules.

For desktop clients expose:

```text
ID_PORT-1/TCP
ID_PORT/TCP
ID_PORT/UDP
RELAY_PORT/TCP
```

Do not open the WebSocket ports unless required.

## 10. Backups

Use menu option 14 before upgrades or major configuration changes.

The backup contains `id_ed25519`; treat it as a secret.
