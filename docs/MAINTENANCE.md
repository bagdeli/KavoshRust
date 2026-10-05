# KavoshRust Maintenance

This document covers routine operations after the first RustDesk Server OSS installation.

## Open the manager

```bash
kavoshrust
```

Useful non-interactive read-only commands:

```bash
kavoshrust --status
kavoshrust --info
kavoshrust --diagnostics
kavoshrust --preflight
```

## Service lifecycle

Use menu items 9-11 to restart, start or stop the KavoshRust stack.

KavoshRust only targets its own Docker Compose project and containers. It does not stop an unrelated web server, VPN, router service or other Docker project.

## Update RustDesk Server

Menu item 13 pulls the current official `rustdesk/rustdesk-server:latest` image and starts the stack again while preserving the persistent data directory.

Before a production update, create a backup.

## Backup

Menu item 14 creates an archive below:

```text
/var/backups/kavoshrust/
```

The archive includes the RustDesk database, server key pair, configuration, Caddy data and generated client settings.

**Treat every backup as a secret**, because it contains `id_ed25519`.

## Restore

Menu item 15 restores a KavoshRust backup. The current deployment is backed up before replacement when possible.

After restore, verify:

```bash
kavoshrust --status
kavoshrust --diagnostics
```

and perform a real client connection test.

## Change public domain

Menu item 5 changes the public hostname advertised by the manager and used by Caddy.

After changing it:

1. Update the DNS A/AAAA records as appropriate.
2. Confirm the DNS record points to this server.
3. Repair/re-enable HTTPS from menu item 7 if needed.
4. Update the ID Server / Relay Server on all RustDesk clients.

## Change RustDesk ports

Menu item 6 asks for a new ID port and Relay port.

Before applying, KavoshRust checks the host ports that RustDesk will publish. A conflicting port is rejected; KavoshRust never kills the process that owns it.

After a port change, also update any provider firewall/security group and every client.

## Force Relay

Menu item 16 toggles `ALWAYS_USE_RELAY`.

- Disabled: RustDesk can use direct peer-to-peer connections when possible.
- Enabled: sessions are forced through your relay, increasing VPS bandwidth consumption.

## WebSocket ports

Menu item 20 enables/disables WebSocket host publishing.

Keep it disabled unless you intentionally deploy a RustDesk web client. Native desktop clients do not need those two WebSocket listeners exposed.

## Logs

Menu item 12 shows hbbs, hbbr or Caddy logs.

Direct examples:

```bash
docker logs --tail 200 kavoshrust-hbbs
docker logs --tail 200 kavoshrust-hbbr
docker logs --tail 200 kavoshrust-caddy
```

## Manager update

Menu item 18 downloads the current `install.sh` from this repository, validates it with `bash -n`, and installs it as the local manager command.

The server runtime configuration remains in `/opt/kavoshrust`.
