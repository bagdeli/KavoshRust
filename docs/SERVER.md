# Server operations

KavoshRust deploys RustDesk Server OSS as two native systemd services:

```text
kavoshrust-hbbs.service
kavoshrust-hbbr.service
```

No Docker backend is used.

## Common commands

```bash
kavoshrust
kavoshrust --status
kavoshrust --info
kavoshrust --diagnostics
```

## Ports

If ID Port is `P` and Relay Port is `R`, RustDesk binds:

```text
P-1/TCP
P/TCP
P/UDP
P+2/TCP
R/TCP
R+2/TCP
```

All five derived TCP port numbers must be free before installation because the native binaries bind them on the host.

For desktop clients, expose only:

```text
P-1/TCP
P/TCP
P/UDP
R/TCP
```

Do not expose `P+2` and `R+2` directly unless a web client is intentionally being used.

## Services

```bash
systemctl status kavoshrust-hbbs
systemctl status kavoshrust-hbbr
journalctl -u kavoshrust-hbbs -f
journalctl -u kavoshrust-hbbr -f
```

The services run as the dedicated `kavoshrust` system user.

## Data

Persistent RustDesk state is under:

```text
/opt/kavoshrust/data/
```

The server private key is:

```text
/opt/kavoshrust/data/id_ed25519
```

Never publish it.

The public client key is:

```text
/opt/kavoshrust/data/id_ed25519.pub
```

## Update

Menu option 13:

1. creates a backup,
2. stores the current binaries for rollback,
3. downloads the latest official RustDesk release,
4. verifies SHA-256 when GitHub publishes a digest,
5. restarts both services,
6. rolls binaries back if the updated services fail.

## SSL

On the current Kavosh server, Nginx already owns 80/443.

KavoshRust creates only:

```text
/etc/nginx/conf.d/kavoshrust.conf
```

It runs `nginx -t` before every reload. Certbot uses webroot mode and renewal reloads Nginx only after validation.

## Firewall

KavoshRust never enables UFW/firewalld automatically.

If a host firewall is already active, KavoshRust manages only the exact RustDesk rules.

If there is no host firewall, use the provider/network firewall to allow the four desktop-client ports and block the two WebSocket ports unless needed.
