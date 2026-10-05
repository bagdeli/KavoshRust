# RustDesk Client Setup for KavoshRust

This guide configures the official RustDesk client to use a KavoshRust self-hosted RustDesk Server OSS instance.

## Get the values from the server

Run:

```bash
kavoshrust
```

Choose:

```text
3) Show server + client connection info
```

The manager prints values like:

```text
ID Server:    rust.example.com:32116
Relay Server: rust.example.com:33117
API Server:   (leave empty for OSS)
Key:          BASE64_PUBLIC_KEY
```

Use the exact values printed by your own server.

## Customer client on Windows

1. Download the official RustDesk client from RustDesk.
2. Run it portable or install it. Install it if you need persistent service/UAC handling.
3. Open **Settings**.
4. Open **Network**.
5. Click **Unlock Network Settings** if elevation is requested.
6. Set **ID Server** to the KavoshRust value, including its custom port.
7. Set **Relay Server** explicitly, including its custom port.
8. Leave **API Server** empty for RustDesk Server OSS.
9. Paste the KavoshRust **public Key** into **Key**.
10. Return to the main screen and confirm the client becomes ready and displays an ID.

Official reference:
https://rustdesk.com/docs/en/self-host/client-configuration/

## Require customer approval

For on-demand support, configure the controlled/customer client so the user must approve the request:

1. Open **Settings**.
2. Open **Security**.
3. Find the password/approval section.
4. Select **Click** / manual approval.

The corresponding setting is:

```text
approve-mode=click
```

Official reference:
https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/#approve-mode

## Technician/operator client

The technician client must use the same:

- ID Server
- Relay Server
- Key

Support flow:

1. Customer opens RustDesk and gives the displayed ID to the technician.
2. Technician enters the ID.
3. Technician starts the connection.
4. Customer sees the incoming request.
5. Customer clicks **Accept**.
6. The remote-control session starts with the allowed permissions.

## Linux and macOS

Use the same network values:

```text
ID Server    = domain:custom_id_port
Relay Server = domain:custom_relay_port
API Server   = empty for OSS
Key          = server public key
```

The exact visual layout can vary by client version, but the upstream manual configuration path is Settings -> Network -> Unlock Network Settings.

## Relay behavior

RustDesk normally attempts a direct P2P connection first. If that fails, it uses your hbbr relay.

Because KavoshRust intentionally uses a non-default relay port, set **Relay Server** explicitly on both clients.

To force every remote session through your server, run `kavoshrust` and choose:

```text
16) Toggle force-relay mode
```

Force relay increases VPS bandwidth usage.

## Troubleshooting

### Server unavailable

Run menu option 17 (**Diagnostics**) on the server. Verify DNS and all printed listeners.

Also check the hosting-provider firewall/security group. KavoshRust can add rules to an already-active UFW/firewalld, but it cannot alter your provider firewall.

### Key mismatch

Copy the **public** key again from menu option 3.

Never send or publish:

```text
/opt/kavoshrust/data/id_ed25519
```

### HTTPS works but RustDesk does not

The HTTPS endpoint on port 443 is only the KavoshRust health/landing endpoint. Native RustDesk uses the custom hbbs/hbbr ports shown by the manager.
