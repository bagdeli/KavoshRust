# KavoshRust Troubleshooting

## First command

Run:

```bash
kavoshrust --diagnostics
```

Then check the specific service logs.

## Client does not receive an ID

Verify:

1. `hbbs` is running.
2. `ID_PORT/TCP` is reachable.
3. `ID_PORT/UDP` is reachable.
4. `ID_PORT-1/TCP` is reachable.
5. Client ID Server includes the custom port.
6. Client Key exactly matches the server public key.
7. Host and provider firewalls allow the ports.

Server checks:

```bash
kavoshrust --status
docker logs --tail 200 kavoshrust-hbbs
```

## Client gets an ID but remote control cannot connect

Check the Relay Server value and `RELAY_PORT/TCP`.

Because KavoshRust uses a non-default relay port, configure Relay Server explicitly:

```text
rust.example.com:CUSTOM_RELAY_PORT
```

Also inspect:

```bash
docker logs --tail 200 kavoshrust-hbbr
```

## Key or secure-handshake errors

Get the current values again:

```bash
kavoshrust --info
```

Copy the public Key exactly into both technician and customer clients, then restart the RustDesk client/service.

Never paste the private `id_ed25519` file into a client.

## Port conflict during install

KavoshRust will refuse the selected layout and show that a required port is busy.

Inspect listeners:

```bash
ss -tulpen
```

or use menu item 4.

Choose different ID/Relay ports. Do not stop an existing service solely to make the installer proceed unless you independently know that service can be removed.

## HTTPS certificate is not issued

Confirm:

- the domain resolves to this server's public IP,
- inbound TCP 80 and 443 are permitted,
- 80/443 are not already owned by another reverse proxy,
- Caddy can reach public ACME endpoints.

Logs:

```bash
docker logs --tail 200 kavoshrust-caddy
```

If a pre-existing Nginx/Apache/Caddy/HAProxy owns 80/443, leave it in place and integrate the hostname there rather than forcing KavoshRust Caddy to replace it.

## Web client fails while native clients work

WebSocket host ports are disabled by default.

Use menu item 20 only when a web client is intentionally required, then configure the corresponding reverse-proxy/firewall policy.

## A port change appears ineffective

Run:

```bash
kavoshrust --info
kavoshrust --status
```

The current manager regenerates the Compose file whenever RustDesk ports change. If this is an older installation, update the manager first with menu item 18 and apply the port change again.

## DNS points somewhere else

Check:

```bash
getent ahostsv4 your.domain.example
curl -4 https://api.ipify.org
```

The public IPv4 should match the intended A record for automatic Caddy validation.
