# KavoshRust

KavoshRust is a safe installer and maintenance manager for **RustDesk Server OSS** on Debian/Ubuntu, designed for shared production servers.

For the current Kavosh deployment, the intended hostname is `rust.kavosh.info`, but the installer always asks for the final domain interactively.

## Why native systemd instead of Docker?

The target Kavosh server already runs Nginx, sing-box, Unbound and other production services. KavoshRust therefore installs the official RustDesk Server binaries directly and manages them with systemd.

This avoids introducing Docker bridge networking or Docker-managed iptables rules on a shared host.

## Quick start

Read-only preflight:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh) --preflight
```

Interactive installation:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh)
```

After installation:

```bash
kavoshrust
```

## Custom ports

You freely choose the main ID and Relay ports. RustDesk itself derives additional listeners:

- `ID_PORT-1/TCP` — NAT test
- `ID_PORT/TCP` — rendezvous / connection
- `ID_PORT/UDP` — registration / heartbeat / hole punching
- `ID_PORT+2/TCP` — hbbs WebSocket listener
- `RELAY_PORT/TCP` — relay
- `RELAY_PORT+2/TCP` — hbbr WebSocket listener

Because native RustDesk binds the WebSocket listeners even when you do not expose them publicly, KavoshRust requires **all five derived host ports to be free before installation**.

The installer rejects any layout touching RustDesk's default range `21115-21119`.

Ports below 1024 are selectable, but KavoshRust warns before using privileged/common ports. The systemd units include only `CAP_NET_BIND_SERVICE` so low ports can work without running RustDesk as root.

For normal desktop clients, only these need to be allowed through the public firewall:

```text
ID_PORT-1/TCP
ID_PORT/TCP
ID_PORT/UDP
RELAY_PORT/TCP
```

KavoshRust does not add allow-rules for the WebSocket ports by default. If no host firewall is active, block those ports in the provider/network firewall unless you intentionally need the web client.

## SSL and existing Nginx

Native RustDesk desktop traffic does not use HTTPS, but KavoshRust can create a health/landing endpoint for the selected hostname.

If DNS points to the server and existing Nginx owns TCP 80/443, KavoshRust:

1. adds only `/etc/nginx/conf.d/kavoshrust.conf`,
2. runs `nginx -t`,
3. reloads Nginx only after validation succeeds,
4. obtains the certificate with Certbot webroot mode,
5. validates Nginx again,
6. enables HTTPS,
7. installs a Certbot renewal deploy hook that validates and reloads Nginx.

If validation or certificate issuance fails, the KavoshRust Nginx change is rolled back. Existing virtual hosts are not replaced.

## Security model

- RustDesk runs as the dedicated `kavoshrust` system user.
- SSH is not changed.
- Existing services are never stopped to free a port.
- UFW/firewalld is never enabled automatically.
- Only KavoshRust's exact firewall rules are added/removed when a host firewall is already active.
- The private key `id_ed25519` stays on the server.
- Only `id_ed25519.pub` is given to clients.
- RustDesk release assets are downloaded from the official GitHub release and SHA-256 verified when the release API provides a digest.

## Manager menu

The interactive manager includes:

1. Install / Repair
2. Status
3. Server/client connection information
4. Port scan
5. Change domain
6. Change RustDesk ports
7. SSL / HTTPS manager
8. Firewall manager
9. Restart
10. Start
11. Stop
12. Logs
13. Update RustDesk binaries with pre-update backup and rollback
14. Backup
15. Restore
16. Force-relay toggle
17. Diagnostics
18. Self-update manager
19. Uninstall
20. WebSocket firewall toggle
21. Read-only preflight

## Files

```text
/opt/kavoshrust/
├── .env
├── bin/
│   ├── hbbs
│   └── hbbr
├── data/
│   ├── id_ed25519
│   └── id_ed25519.pub
├── client-config.txt
├── version
└── nginx-site.conf     # copy of KavoshRust vhost when SSL is enabled

/etc/systemd/system/kavoshrust-hbbs.service
/etc/systemd/system/kavoshrust-hbbr.service
/etc/nginx/conf.d/kavoshrust.conf
/var/backups/kavoshrust/
/var/log/kavoshrust-manager.log
```

## Client configuration

Run:

```bash
kavoshrust --info
```

Then configure both technician and customer RustDesk clients with the exact displayed:

- ID Server
- Relay Server
- Key

Leave API Server empty for OSS.

See [docs/CLIENT.md](docs/CLIENT.md).

## Documentation

- [Persian guide](docs/FA.md)
- [Client setup](docs/CLIENT.md)
- [Server operations](docs/SERVER.md)
- [Kavosh deployment checklist](docs/KAVOSH-DEPLOYMENT.md)
- [Maintenance](docs/MAINTENANCE.md)
- [Security](docs/SECURITY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Upstream

- RustDesk Server OSS: https://github.com/rustdesk/rustdesk-server
- RustDesk install docs: https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/
- Client configuration: https://rustdesk.com/docs/en/self-host/client-configuration/

RustDesk Server OSS is a separate upstream project licensed under AGPL-3.0.
