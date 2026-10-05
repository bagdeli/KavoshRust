# KavoshRust

KavoshRust is an installer and maintenance manager for a **self-hosted RustDesk Server OSS** deployment on Debian/Ubuntu. It is designed for shared production servers where existing services must not be interrupted.

## Main goals

- Install RustDesk OSS with Docker Compose.
- Ask for the public domain during installation.
- Use **non-default, user-selected RustDesk ports**.
- Detect occupied ports before any RustDesk service is started.
- Publish only the RustDesk ports actually needed; WebSocket ports are off by default.
- Never stop or reconfigure an unrelated service to free a port.
- Automatically provision HTTPS with Caddy when TCP 80/443 are available.
- Preserve existing firewall policy; only add RustDesk rules when UFW/firewalld is already active.
- Print the exact ID Server, Relay Server and public Key required by RustDesk clients.
- Provide a menu for routine operations, diagnostics, updates, backup/restore and uninstall.

## Quick install

Run a read-only preflight first:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh) --preflight
```

Then start the interactive installer as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh)
```

After the first installation, the same manager is installed as:

```bash
kavoshrust
```

## Port model

RustDesk Server OSS uses two server processes: `hbbs` (ID/rendezvous) and `hbbr` (relay). Upstream RustDesk ties several listeners to the selected base ports:

- `hbbs`: `ID_PORT-1/TCP` for NAT test
- `hbbs`: `ID_PORT/TCP+UDP` for rendezvous/heartbeat/hole punching
- `hbbs`: `ID_PORT+2/TCP` for WebSocket
- `hbbr`: `RELAY_PORT/TCP` for relay
- `hbbr`: `RELAY_PORT+2/TCP` for WebSocket relay

The installer lets you choose `ID_PORT` and `RELAY_PORT`. It computes the dependent ports, verifies that all five are distinct and free, and rejects a layout that would collide with any currently listening service. This keeps the deployment compatible with the official RustDesk client instead of relying on fragile external port remapping.

The installer deliberately suggests high, non-default ports. Native desktop clients normally need these public firewall rules:

- `ID_PORT-1/TCP`
- `ID_PORT/TCP`
- `ID_PORT/UDP`
- `RELAY_PORT/TCP`

WebSocket ports are not published by the safe default because the native desktop client does not require them. KavoshRust uses Docker bridge networking with explicit port publishing so unused RustDesk listeners stay isolated inside their containers. Menu option 20 can publish the derived WebSocket ports later if a web client is introduced.

Upstream references:

- https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/
- https://github.com/rustdesk/rustdesk-server/blob/master/docs/environment-variables.md

## Automatic SSL

RustDesk OSS native desktop traffic does **not** require HTTPS. KavoshRust nevertheless provisions an HTTPS health/landing endpoint for the chosen domain because it is useful for domain validation, monitoring, and future integrations.

If ports 80 or 443 are already occupied, KavoshRust **does not stop the existing service**. Bundled Caddy is skipped and the rest of RustDesk installs normally. You can later use menu item `SSL / HTTPS manager` after integrating the domain with your existing reverse proxy or freeing those ports.

When 80/443 are free, Caddy obtains and renews the public certificate automatically after DNS points to the server.

## Menu

The manager currently provides:

1. Install / Repair RustDesk OSS
2. Status
3. Show server + client connection info
4. Scan/list occupied ports
5. Change domain
6. Change RustDesk ports
7. SSL / HTTPS manager
8. Firewall rules manager
9. Restart services
10. Start services
11. Stop services
12. View logs
13. Update RustDesk containers
14. Backup server
15. Restore backup
16. Toggle force-relay mode
17. Diagnostics
18. Update manager script
19. Uninstall RustDesk service
20. Enable/disable WebSocket ports
21. Safe preflight report

## Files on the server

```text
/opt/kavoshrust/
├── .env
├── compose.yml
├── Caddyfile
├── client-config.txt
├── data/               # RustDesk DB and Ed25519 keys
├── caddy_data/         # TLS certificates (when enabled)
├── caddy_config/
└── www/

/var/backups/kavoshrust/
/usr/local/sbin/kavoshrust
/var/log/kavoshrust-manager.log
```

The backup contains the RustDesk private key and must be treated as a secret.

## Client setup

See [docs/CLIENT.md](docs/CLIENT.md) for exact Windows/Linux/macOS client configuration and the click-to-approve support workflow.

## Server operations

See [docs/SERVER.md](docs/SERVER.md) for port planning, DNS, SSL, firewall behavior, backup/restore, diagnostics and safe operation on a shared server.

## Security notes

- Do not publish `id_ed25519` (private key).
- Only `id_ed25519.pub` is given to clients.
- The installer will not enable UFW/firewalld or alter the firewall default policy.
- Provider/cloud firewalls still need the same RustDesk ports opened.
- For on-demand support, configure the controlled client to require manual approval (`approve-mode=click`).

## License

This repository contains deployment tooling. RustDesk Server itself is a separate upstream project and is licensed under AGPL-3.0. Review RustDesk's upstream license before redistribution or modification.
