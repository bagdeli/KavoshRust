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


## One-way connection: client can connect out, but its ID says "ID does not exist"

This pattern usually means the affected client can reach hbbs for outbound signaling but is not successfully registered/heartbeating on the self-hosted ID server.

Check the affected client first:

```text
ID Server:    rust.kavosh.info:45116
Relay Server: rust.kavosh.info:46117
Key:          exact value from kavoshrust --info
API Server:   empty for OSS
```

Then fully restart RustDesk (including the installed Windows service if present).

On the server, use manager option 22 or:

```bash
tcpdump -ni any -vv 'udp port 45116'
```

Restart the affected client while capturing.

Interpretation:

- No UDP packets from the client: wrong ID Server/config, client is still using public RustDesk servers, or the remote network/firewall blocks UDP 45116.
- UDP packets arrive but no useful registration follows: verify the exact server public key and inspect hbbs/client logs.
- UDP traffic is bidirectional and the client still is not discoverable: inspect the client config file/logs and client version.

For installed Windows RustDesk, relevant files are commonly under:

```text
C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml
C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\log\server\
```

Portable/user-side config and logs are under:

```text
%AppData%\RustDesk\config\RustDesk2.toml
%AppData%\RustDesk\log\RustDesk_rCURRENT.log
```

If GUI settings were changed but the client still uses a public rendezvous server, inspect `RustDesk2.toml` while RustDesk is fully stopped and confirm the effective rendezvous/custom-server values.
