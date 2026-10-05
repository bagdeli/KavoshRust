# KavoshRust Server Operations

## Supported systems

KavoshRust targets Debian and Ubuntu and must be run as root. RustDesk Server OSS is deployed through Docker Compose.

## Shared-server safety

KavoshRust uses Docker bridge networking and explicitly publishes only the required host ports. WebSocket ports are not published by default.

Before starting RustDesk, the installer:

1. installs basic prerequisites,
2. lists current listeners,
3. asks for the public domain,
4. suggests non-default high ports but permits any valid custom base ports,
5. checks every RustDesk listener implied by the selected ports,
6. rejects collisions,
7. checks whether 80/443 are free before starting bundled Caddy,
8. only adds firewall rules when UFW/firewalld is already active,
9. reports routing state and requires confirmation before installing Docker when IPv4 forwarding is enabled.

It never stops an unrelated process just to claim its port.

For a read-only inventory before installation:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh) --preflight
```

## Router / forwarding hosts

Before installing Docker on a host that already has `net.ipv4.ip_forward=1`, KavoshRust prints routes and policy rules and asks for explicit confirmation. This is intentional: Docker can modify iptables/FORWARD behavior. Cancelling at that point leaves Docker and RustDesk uninstalled.

## DNS

Create an A record such as:

```text
rust.kavosh.info -> SERVER_PUBLIC_IPV4
```

If DNS is not propagated during installation, RustDesk can still be installed. Caddy will retry certificate issuance after DNS becomes correct.

## RustDesk custom ports

For ID port P:

```text
P-1/TCP  NAT type test
P/TCP    ID/rendezvous
P/UDP    registration/heartbeat/hole punching
P+2/TCP  ID WebSocket
```

For relay port R:

```text
R/TCP    relay
R+2/TCP  relay WebSocket
```

These relationships are imposed by the RustDesk Server binaries. Therefore KavoshRust lets you choose P and R, then validates every derived port before launch. Low/privileged ports are selectable but generate a warning. The derived ranges mean `P` must be `2..65533`, and `R` must be `1..65533`.

Upstream reference:
https://github.com/rustdesk/rustdesk-server/blob/master/docs/environment-variables.md

## Essential firewall rules for native desktop clients

```text
ID_PORT-1/TCP
ID_PORT/TCP
ID_PORT/UDP
RELAY_PORT/TCP
```

Provider/cloud firewalls must be configured separately.

KavoshRust never enables a host firewall automatically, because enabling one on an existing server can disrupt SSH or other applications.

## HTTPS / SSL

Bundled Caddy uses:

```text
80/TCP
443/TCP
443/UDP
```

If port 80 or 443 is already occupied, Caddy is skipped and RustDesk installation continues. This protects existing web/reverse-proxy services.

SSL is for the HTTPS health/landing endpoint; the native RustDesk protocol uses its own ports and server public key.

## Files

```text
/opt/kavoshrust/.env
/opt/kavoshrust/compose.yml
/opt/kavoshrust/Caddyfile
/opt/kavoshrust/client-config.txt
/opt/kavoshrust/data/
/opt/kavoshrust/caddy_data/
/var/backups/kavoshrust/
/var/log/kavoshrust-manager.log
/usr/local/sbin/kavoshrust
```

## Backup

Menu option 14 creates a timestamped archive under:

```text
/var/backups/kavoshrust/
```

The archive contains the RustDesk private key and must be protected.

## Restore

Menu option 15 creates a safety backup of the current deployment, restores the selected archive, and starts the stack again.

## Update

Menu option 13 pulls the latest RustDesk Server OSS container and recreates the services while keeping persistent data and keys.

## Change ports

Menu option 6 validates the new layout before stopping RustDesk. It restarts only the RustDesk containers.

After a port change, update all clients and external/provider firewall rules.

## Change domain

Menu option 5 updates the relay advertisement and Caddy configuration. Update DNS and every RustDesk client accordingly.

## Force relay

Default operation permits direct P2P when possible, reducing VPS bandwidth.

Menu option 16 toggles `ALWAYS_USE_RELAY=Y` if policy requires all remote desktop traffic to traverse the server.

## Uninstall

Menu option 19 removes only KavoshRust containers first. Data deletion is separately confirmed. Docker and existing firewall rules are intentionally retained because they may be shared with other services.


## Kavosh production naming

For the current Kavosh deployment, the intended public name is:

```text
rust.kavosh.info
```

The installer does not hard-code it; the domain is requested interactively so the same repository remains reusable on other hosts. Create or update the DNS A record before installation when possible.

If the shared server already owns TCP 80/443 through another reverse proxy, KavoshRust deliberately does not replace or stop it. RustDesk native desktop access remains usable on its selected custom ports; integrate the HTTPS hostname into the existing reverse proxy separately if an HTTPS landing/health endpoint is required.
