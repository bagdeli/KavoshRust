# KavoshRust Security Notes

## Shared-server safety model

The installer is intentionally conservative:

- It checks candidate RustDesk host ports before starting containers.
- It does not stop an unknown process to free a port.
- It does not modify SSH configuration.
- It does not enable UFW/firewalld if the firewall is currently inactive.
- It does not replace an existing service on TCP 80/443.
- It runs RustDesk in Docker bridge mode and publishes only required ports.
- WebSocket ports are not published by default.

## Server keys

Runtime key files are stored under:

```text
/opt/kavoshrust/data/id_ed25519
/opt/kavoshrust/data/id_ed25519.pub
```

`id_ed25519` is private and must never be shared.

Only the public key content from `id_ed25519.pub` is entered into clients.

KavoshRust starts hbbs first, waits for the shared key pair, then starts hbbr with key validation enabled against the same mounted key material.

## SSH

KavoshRust deliberately leaves SSH untouched. On a production host you should separately consider:

- SSH public-key authentication
- limiting direct root login
- administrative IP allowlisting or a management VPN
- brute-force protection
- off-server backups

Do these only with a recovery path available; changing SSH/firewall settings on a remote shared server can lock administrators out.

## Host firewall

When UFW or firewalld is already active, KavoshRust adds the required RustDesk rules.

When neither is active, it prints the required ports but does not activate a firewall automatically.

A cloud/provider firewall is independent of the host firewall and must be configured separately.

## Default RustDesk ports

KavoshRust intentionally rejects a public host-port layout that uses RustDesk's default range `21115-21119`. The goal is not security by obscurity; it is operational separation and avoidance of collisions with another RustDesk deployment.

Authentication still depends on the RustDesk server key and client access policy.

## Customer approval

For on-demand support, configure controlled/customer clients with manual approval:

```text
approve-mode=click
```

Do not enable unattended access globally unless the business workflow requires it.

## HTTPS

HTTPS managed by Caddy protects the informational/health endpoint on the selected hostname. Native RustDesk traffic is not HTTP traffic and does not run through that HTTPS listener.

Caddy is not started if 80/443 are already occupied by another service.

## Public repository hygiene

Never commit:

- server private keys
- backups
- passwords
- access tokens
- generated runtime `.env`
- customer-specific credentials

The repository `.gitignore` excludes the common KavoshRust runtime/secret files, but operators must still review commits before pushing.
