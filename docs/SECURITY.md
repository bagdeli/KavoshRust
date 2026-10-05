# Security

## Existing services

KavoshRust is designed not to stop or replace unrelated services.

On a shared host it:

- does not change SSH,
- does not install Docker,
- does not replace Nginx,
- does not enable a disabled host firewall,
- refuses occupied RustDesk ports,
- validates Nginx before reload.

## RustDesk identity keys

Keep this private:

```text
/opt/kavoshrust/data/id_ed25519
```

Clients receive only:

```text
/opt/kavoshrust/data/id_ed25519.pub
```

Backups contain the private key and must be protected.

## WebSocket ports

Native RustDesk binds `ID+2/TCP` and `Relay+2/TCP`.

RustDesk upstream recommends keeping WebSocket ports closed when the web client is not used. If there is no local firewall, block those ports in the provider/network firewall.

## Process privilege

RustDesk runs as the dedicated `kavoshrust` system user, not root.

The systemd units receive `CAP_NET_BIND_SERVICE` only so that explicitly selected ports below 1024 can still work.

## TLS

HTTPS is separate from native RustDesk traffic.

For the Kavosh production server, certificates are obtained with Certbot using the existing Nginx. KavoshRust writes one isolated vhost and validates the whole Nginx configuration before reload.

## Credentials

Do not place SSH passwords, private keys, API tokens or server private keys in the public GitHub repository.
