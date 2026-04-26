---
kind: runbook
tags: [backup, restic, sanoid, zfs]
---

# Backup and Restore Runbook

## Overview

Two-layer backup on pebble:
1. **Sanoid** — ZFS snapshots (local, fast, no NAS dependency)
2. **Restic** — Daily to Synology NAS via NFS (disaster recovery)

VPS: not backed up (minimal state, re-provisionable from flake).

**Full details:** [docs/roadmap/stage-10-hardening-backups.md](../roadmap/stage-10-hardening-backups.md), `homelab/backup/default.nix`

---

## What Is Backed Up

### Sanoid (ZFS snapshots)
- `zroot/var` — all service state (`/var/lib/*`)
- `zroot/home` — admin home

### Restic (NAS)
- `/var/lib` — all service state
- `/var/backup/vaultwarden` — SQLite dumps

### NOT backed up
- System config (in Git)
- `/nix/store` (reproducible)
- `/tmp`, `/var/tmp` (ephemeral)
- VPS (re-provisionable)

---

## Sanoid Schedule

Automated ZFS snapshots (local, no NAS):
- **Hourly:** 24 snapshots
- **Daily:** 30 snapshots
- **Monthly:** 6 snapshots

```bash
ssh admin@192.168.10.50
zfs list -t snapshot | grep auto_
```

---

## Restic to NAS

Daily backups to Synology at `192.168.10.100` via NFSv4.1.

**Repository:** `/mnt/nas/backup/restic/homelab` (NFS-mounted from Synology `volume1/zfs-backups`)

**Retention:** Daily 7, Weekly 5, Monthly 12

**Synology NFS:** IP `192.168.10.50`, squash = "No mapping"

---

## Verifying Backups

### Sanoid

```bash
ssh admin@192.168.10.50

zfs list -t snapshot | grep hourly | wc -l  # should be ~24
systemctl status sanoid.timer
journalctl -u sanoid.service
```

### Restic

```bash
ssh admin@192.168.10.50

restic -r /mnt/nas/backup/restic/homelab snapshots
# Password: from /run/secrets/restic/password

systemctl status restic-backups-homelab.service
mount | grep /mnt/nas/backup
```

---

## Restore from ZFS Snapshot (Fast)

Use for recent recovery (within 24h–6mo).

```bash
# List snapshots
zfs list -t snapshot | grep zroot/var

# Browse snapshot
ls /var/.zfs/snapshot/autosnap_2026-04-18_12:00:00_hourly/lib/grafana/

# Restore specific file
cp /var/.zfs/snapshot/autosnap_2026-04-18_12:00:00_hourly/lib/grafana/grafana.db \
   /var/lib/grafana/grafana.db
chown grafana:grafana /var/lib/grafana/grafana.db
systemctl restart grafana

# Restore entire dataset (DESTRUCTIVE — destroys changes after snapshot)
systemctl stop caddy pihole grafana loki prometheus vaultwarden kanidm home-assistant
zfs rollback zroot/var@autosnap_2026-04-18_12:00:00_hourly
systemctl start caddy pihole grafana loki prometheus vaultwarden kanidm home-assistant
```

---

## Restore from Restic (Disaster Recovery)

```bash
# List backups
restic -r /mnt/nas/backup/restic/homelab snapshots

# Restore to original location
restic -r /mnt/nas/backup/restic/homelab restore latest --target /

# Restore to temp location for inspection
restic -r /mnt/nas/backup/restic/homelab restore latest --target /tmp/restore

# Restore specific path only
restic -r /mnt/nas/backup/restic/homelab restore latest \
  --target / --include /var/lib/grafana

# Restore from specific snapshot ID
restic -r /mnt/nas/backup/restic/homelab restore a1b2c3d4 --target /
```

---

## Bare-Metal Recovery

1. **Provision base system** — `just deploy pebble` (Stage 1 workflow)
2. **Mount NAS** — `ls /mnt/nas/backup` (triggers automount)
3. **Restore from Restic:**
   ```bash
   restic -r /mnt/nas/backup/restic/homelab restore latest --target /
   ```
4. **Fix permissions:**
   ```bash
   chown -R grafana:grafana /var/lib/grafana
   chown -R vaultwarden:vaultwarden /var/lib/vaultwarden
   # etc.
   ```
5. **Restart services:**
   ```bash
   systemctl restart caddy pihole grafana loki prometheus vaultwarden kanidm home-assistant
   ```
6. **Verify:** `systemctl status <service>`, test web UIs

---

## Troubleshooting

**Sanoid not creating snapshots:** `systemctl status sanoid.timer`, `systemctl list-timers | grep sanoid`, `journalctl -u sanoid.service`. Manual trigger: `sudo systemctl start sanoid.service`.

**Restic failing:** `systemctl status restic-backups-homelab.service`, `journalctl -u restic-backups-homelab`. Common causes: NFS not mounted (`mount | grep /mnt/nas`, `ls /mnt/nas/backup`), password missing (`ls -l /run/secrets/restic/password`), NAS unreachable (`ping 192.168.10.100`). Manual test: `restic -r /mnt/nas/backup/restic/homelab snapshots`.

**NFS mount fails:** `ping 192.168.10.100`. Check Synology: DSM → Control Panel → File Services → NFS (enabled), Shared Folder → zfs-backups → NFS Permissions (rule: 192.168.10.50, squash "No mapping"). Manual mount: `sudo mount -t nfs -o nfsvers=4.1 192.168.10.100:/volume1/zfs-backups /mnt/nas/backup`. Check systemd: `systemctl status mnt-nas-backup.automount`, `journalctl -u mnt-nas-backup.mount`.

---

## References

- homelab/backup/default.nix — Sanoid + Restic config
- Stage 10: Backup implementation — [docs/roadmap/stage-10-hardening-backups.md](../roadmap/stage-10-hardening-backups.md)
- Sanoid — https://github.com/jimsalterjrs/sanoid
- Restic — https://restic.net/
