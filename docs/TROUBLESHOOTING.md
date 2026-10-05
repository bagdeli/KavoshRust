# Troubleshooting

## Client cannot register

Run:

```bash
kavoshrust --status
kavoshrust --info
```

Verify that the client uses the exact ID Server and public Key shown by the server.

Confirm external access to:

```text
ID_PORT-1/TCP
ID_PORT/TCP
ID_PORT/UDP
```

## Relay fails

Verify:

```text
RELAY_PORT/TCP
```

is reachable and that the client has the explicit non-default Relay Server value.

## Service fails to start

```bash
journalctl -u kavoshrust-hbbs -n 100 --no-pager
journalctl -u kavoshrust-hbbr -n 100 --no-pager
```

Then check the configured listeners:

```bash
ss -tulpen
```

A port conflict must be resolved by choosing another RustDesk port pair; do not stop unrelated production services.

## SSL fails

First check DNS:

```bash
dig +short rust.kavosh.info
```

It must resolve to the server public IP.

Then validate Nginx:

```bash
nginx -t
```

Use menu option 7 to retry HTTPS.

KavoshRust uses Certbot webroot mode, so TCP 80 must remain publicly reachable for HTTP-01 validation.

## HTTPS works but RustDesk does not

HTTPS is not the RustDesk desktop transport. Check the custom RustDesk TCP/UDP ports separately.

## WebSocket warning

If no UFW/firewalld is active, closing WebSocket access in the KavoshRust menu cannot create a local firewall by itself. Block `ID+2/TCP` and `Relay+2/TCP` in the provider/network firewall if they are not needed.
