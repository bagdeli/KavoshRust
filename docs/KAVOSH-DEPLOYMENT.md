# Kavosh deployment checklist

This document is the deployment checklist for running KavoshRust on the same public server that currently serves `kavoshrepo.kavosh.info`.

The intended RustDesk public hostname is:

```text
rust.kavosh.info
```

The installer still asks for the hostname interactively; it is not hard-coded.

## 1. DNS

Create an A record for `rust.kavosh.info` pointing to the public IPv4 address of the target server.

If IPv6 is in use, only create an AAAA record after confirming the service and firewall are correctly reachable over IPv6.

## 2. Run the read-only preflight

Before installing anything:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh) --preflight
```

This does not install or change services. Review:

- existing TCP/UDP listeners and owning processes,
- whether Docker and Docker Compose already exist,
- whether TCP/UDP 80 and 443 are occupied,
- CPU, memory and root filesystem capacity.

## 3. Installation

Start the interactive manager:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh)
```

Choose **1 - Install / Repair RustDesk OSS**.

When asked for the domain, enter:

```text
rust.kavosh.info
```

For the RustDesk ID and Relay ports, either accept the high non-default free ports suggested by KavoshRust or enter your own high ports. The manager rejects a selection if any host-published RustDesk port conflicts with an existing listener. WebSocket-derived ports are checked only if WebSocket publishing is enabled.

### RustDesk port relationships

If ID port is `P`:

- `P-1/TCP` — NAT test
- `P/TCP` — rendezvous / connection
- `P/UDP` — registration, heartbeat, hole punching
- `P+2/TCP` — WebSocket (not published by default)

If Relay port is `R`:

- `R/TCP` — relay
- `R+2/TCP` — WebSocket relay (not published by default)

The derived ports are an upstream RustDesk behavior and cannot be independently assigned when using the official OSS binaries.

## 4. HTTPS / certificate behavior

If host ports 80 and 443 are free, KavoshRust starts its isolated Caddy container. Caddy automatically obtains and renews a public certificate for the selected domain after DNS resolves correctly.

If either port is already occupied, KavoshRust does not stop, replace, or reconfigure the existing service. RustDesk itself still installs and works on its custom ports.

On a shared web server, the preferred long-term approach is to add `rust.kavosh.info` to the existing reverse proxy instead of starting a second listener on 80/443.

The native RustDesk desktop protocol does not use this HTTPS endpoint; the HTTPS endpoint exists for domain validation, health checks and future web integrations.

## 5. Firewall

KavoshRust only adds rules when UFW or firewalld is already active. It does not enable a firewall or modify the default policy.

For native RustDesk clients, allow the values printed by the manager:

```text
ID_PORT-1/TCP
ID_PORT/TCP
ID_PORT/UDP
RELAY_PORT/TCP
```

Do the same in any provider-side firewall/security group.

Do not expose the WebSocket ports unless a web client is actually needed.

## 6. Validate after installation

Run:

```bash
kavoshrust --status
kavoshrust --info
```

The server information output contains:

- ID Server
- Relay Server
- public server Key
- actual custom ports
- SSL state
- force-relay state

For a deeper report:

```bash
kavoshrust --diagnostics
```

## 7. Configure clients

Configure both the technician and customer RustDesk clients with the exact values returned by `kavoshrust --info`.

For the customer-side on-demand support model, configure manual approval (`approve-mode=click`) so the customer must accept an incoming support connection.

See [CLIENT.md](CLIENT.md) for the full client procedure.

## 8. Back up before future changes

From the interactive menu use **Backup server** before changing domain, ports or performing major maintenance. Backups include the RustDesk private key; store them as secrets.

## 9. Shared-server rule

If any requested port belongs to an existing service, do not stop that service merely to install RustDesk. Choose another RustDesk base/relay port instead. For 80/443, reuse the existing reverse proxy outside KavoshRust rather than replacing it.
