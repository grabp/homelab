---
service: backup
stage: 10a
machine: pebble, boulder
status: deployed
---

# Backup

## Purpose

Two-layer backup strategy:

1. **Sanoid** — ZFS snapshot management (hourly/daily/monthly snapshots of
   `zroot/var` and `zroot/home`)
2. **Restic** — encrypted off-machine backup to a Synology NAS over NFS
   (`/mnt/nas/backup/restic/<hostname>` — one repo per machine)

## Ports

None — backup is outbound only (NFS mount + restic push).

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `restic/password` | plaintext passphrase | Restic repository encryption key |

## Depends on

- NAS NFS export: `<nasIP>:/volume1/zfs-backups` mounted at `/mnt/nas/backup`
  via `x-systemd.automount` (lazy mount, times out after 600s idle)
- ZFS pool `zroot` (datasets `zroot/var` and `zroot/home`)

## DNS

Not applicable — NAS accessed by IP (`vars.nasIP`).

## OIDC

Not applicable.

## Sanoid snapshot schedule

| Retention | Count |
|-----------|-------|
| Hourly    | 24    |
| Daily     | 30    |
| Monthly   | 6     |

Datasets: `zroot/var`, `zroot/home`.

## Restic backup schedule

- **Frequency:** daily (systemd timer, persistent)
- **Paths:** configurable via `my.services.backup.paths` (default: `/var/lib`, `/var/backup`)
- **Pruning:** keep 7 daily, 5 weekly, 12 monthly

The `/var/backup` default covers all service dumps (Vaultwarden SQLite, PostgreSQL
logical dumps) without per-service path configuration.

## Known gotchas

- `x-systemd.automount` with `nofail` — restic timer waits for the NFS mount;
  if NAS is unreachable, backup fails gracefully without blocking boot.
- `restic-backups-homelab.service` has `after` + `requires` on the automount
  unit to ensure NFS is mounted before restic runs.
- Restic password is the **only** key to decrypt the repository — store a copy
  in Vaultwarden and/or offline. Loss = permanent data loss.
- ZFS snapshots are local (on-disk); they protect against accidental deletion
  but not against disk failure. Restic provides the off-site copy.

## Backup / restore

Repository path is `/mnt/nas/backup/restic/<hostname>` (e.g. `restic/pebble`,
`restic/boulder`). The `restic-homelab` wrapper on each machine pre-sets the
password file.

To list snapshots:
```bash
sudo restic-homelab -r /mnt/nas/backup/restic/pebble snapshots
```
To restore from restic:
```bash
sudo restic-homelab -r /mnt/nas/backup/restic/pebble restore latest --target /
```
Password file is at `/run/secrets/restic/password` on a running system.

### NAS NFS permissions
Each machine's IP must be allowed in Synology DSM → Shared Folder →
`zfs-backups` → NFS Permissions. Add a rule per machine (squash: No mapping).
