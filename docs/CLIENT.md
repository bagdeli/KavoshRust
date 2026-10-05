# RustDesk client configuration

After the server installation, run:

```bash
kavoshrust --info
```

You will receive values similar to:

```text
ID Server:    rust.kavosh.info:45116
Relay Server: rust.kavosh.info:46117
Key:          <server public key>
```

Use the exact values displayed by your own server.

## Technician client

In RustDesk:

1. Open **Settings**.
2. Open **Network**.
3. Unlock network settings if required.
4. Set **ID Server** to the displayed domain and ID port.
5. Set **Relay Server** to the displayed domain and Relay port.
6. Set **Key** to the displayed public key.
7. Leave **API Server** empty for RustDesk Server OSS.

Restart RustDesk if necessary.

## Customer client

Configure the same ID Server, Relay Server and Key.

For the support model where the customer must approve the session, use manual approval rather than permanent unattended access.

The intended flow is:

```text
Customer opens RustDesk
        ↓
Customer gives support technician the RustDesk ID
        ↓
Technician enters that ID
        ↓
Customer receives connection request
        ↓
Customer chooses Accept / Reject
```

For deployments where you manage advanced settings centrally or build a preconfigured client later, the relevant RustDesk setting is `approve-mode=click`.

## Why Relay Server is explicit

Because KavoshRust deliberately uses a non-default relay port, set the Relay Server explicitly instead of relying on default-port deduction.

## API Server

Leave API Server empty for OSS. It is used by RustDesk Server Pro features.

## WebSocket ports

Native `hbbs` and `hbbr` create their WebSocket listeners on derived ports, but KavoshRust keeps them closed in the firewall by default. Desktop clients do not need them.

## Security

Give customers only the public server key shown by `kavoshrust --info`.

Never distribute:

```text
/opt/kavoshrust/data/id_ed25519
```

That file is the server private key.
