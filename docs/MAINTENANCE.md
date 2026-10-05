# Maintenance

Open the manager:

```bash
kavoshrust
```

## Status

```bash
kavoshrust --status
```

Checks both systemd services and all expected RustDesk listeners.

## Diagnostics

```bash
kavoshrust --diagnostics
```

Shows service state, DNS, listeners, recent journal logs and Nginx validation.

## Backup

Menu option 14 creates:

```text
/var/backups/kavoshrust/kavoshrust-YYYYMMDD-HHMMSS.tar.gz
```

Back up before port/domain changes or updates.

## Restore

Menu option 15 restores the selected archive and regenerates systemd units.

Re-enable HTTPS afterward if required.

## Update RustDesk

Menu option 13 downloads the latest official release. A backup and binary rollback copy are created before restart.

## Change ports

Menu option 6 validates the complete new native listener set before stopping services. If the new services fail, KavoshRust restores the old ports and attempts to restart the previous configuration.

After a successful change, update client settings and provider firewall rules.

## Change domain

Menu option 5 restarts only KavoshRust services. Existing KavoshRust HTTPS is disabled first; after DNS points to the new name, enable SSL from menu option 7.

## Logs

Menu option 12 uses `journalctl` for hbbs/hbbr.

## Uninstall

Menu option 19 removes KavoshRust systemd services and its Nginx vhost. Nginx itself, Certbot packages and certificate files are left in place to avoid affecting other applications.
