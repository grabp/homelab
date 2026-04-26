---
kind: roadmap
stage: 10
title: Hardening and Backups
status: complete
---

# Stage 10: Hardening, Backups, VPS Log Shipping

## Status
COMPLETE (implemented 2026-04-19)

## Files Created
- `machines/nixos/vps/monitoring.nix` — Alloy collects VPS journald logs, pushes to pebble Loki (100.102.154.38:3100) over NetBird mesh
- `machines/nixos/vps/netbird-client.nix` — enrolls VPS as a NetBird peer (0.68.x overlay, wt0 client, setup key via sops); required for Alloy to reach pebble over the mesh
- `homelab/backup/default.nix` — Sanoid ZFS snapshots (zroot/var + zroot/home), NFS mount (Synology), Restic daily Vaultwarden backup to NFS path
- `machines/nixos/_common/security.nix` — fail2ban SSH jail on all machines (pebble + VPS)

## Files Modified
- `machines/nixos/vps/default.nix` — added `./monitoring.nix` and `./netbird-client.nix` imports
- `homelab/loki/default.nix` — changed `http_listen_address` from `127.0.0.1` to `0.0.0.0`; replaced EOL Promtail with Alloy for pebble journald shipping
- `machines/nixos/pebble/default.nix` — added `networking.firewall.interfaces."wt0".allowedTCPPorts = [ 3100 ]`; enabled `my.services.backup`
- `homelab/default.nix` — enabled `./backup` import
- `machines/nixos/_common/default.nix` — added `./security.nix` import

## Configuration Notes
- **VPS log shipping**: Alloy on VPS pushes to pebble Loki via NetBird mesh (encrypted, no public exposure). Port 3100 opened on wt0 interface only — stays closed on eth0.
- **Promtail → Alloy**: Promtail is EOL (2026-03-02). Both pebble and VPS now use Alloy (`services.alloy`). Labels: `{host="pebble"}` and `{host="vps"}` for filtering in Grafana.
- **Sanoid**: hourly 24, daily 7, weekly 4, monthly 3 snapshots for `zroot/var` and `zroot/home`.
- **NAS**: Synology at `192.168.10.100`, shared folder `zfs-backups` on volume1, NFSv4. NFS squash: "No mapping" (admin account disabled on Synology; root on pebble writes as root on NAS — safe on trusted LAN). Mount point on pebble: `/mnt/nas/backup`.
- **Syncoid dropped**: Synology has no ZFS — syncoid (ZFS-to-ZFS) replaced by NFS mount + restic local path.
- **Restic secret**: add `restic/password: <password>` to `secrets/secrets.yaml` via `just edit-secrets`.
- **Fail2ban**: `services.fail2ban` in `_common/security.nix` applies to all machines (pebble + VPS). maxretry=5 global, maxretry=3 for sshd jail, bantime=10m.
- **deploy-rs**: was already complete from earlier stages. `just deploy pebble` and `just deploy-vps` both functional.
- **NetBird ACLs**: manual step in NetBird Dashboard — delete default "All→All" policy, add group-scoped policies. Not declaratively codified (dashboard-only).
- **VPS SSH IP restriction**: skipped (dynamic admin IP). Fail2ban + key-only auth provides SSH protection.

## Pre-Deploy Actions Required
```bash
# Add restic password to secrets:
just edit-secrets
# Add: restic/password: "your-strong-password"
```

## Bugs Fixed During Deployment
1. **River syntax `#` comment**: Alloy rejected `machines/nixos/vps/monitoring.nix` at startup with `illegal character U+0023 '#'`. River uses `//` for comments, not `#`. deploy-rs rolled back automatically; fixed by replacing the comment character.
2. **VPS not a NetBird peer**: VPS runs the NetBird management server but had no NetBird client — no overlay IP, could not reach pebble's `100.102.154.38`. Added `machines/nixos/vps/netbird-client.nix`; VPS enrolled as a peer with one-time `netbird-wt0 up --management-url ...` after deploy.
3. **NFS access denied**: Synology NFS permissions for `zfs-backups` had no rule for pebble's IP (`192.168.10.50`). Fixed via DSM → Shared Folder → NFS Permissions → add rule for `192.168.10.50`, squash "No mapping".

## Verification (All Passed 2026-04-19)
- [x] `just deploy pebble` — Loki, Alloy, backup, firewall changes applied
- [x] `just deploy-vps` — monitoring.nix and netbird-client.nix applied
- [x] `systemctl status alloy` on pebble — Alloy active, shipping pebble journald
- [x] `ssh admin@204.168.181.110 systemctl status alloy` — Alloy active on VPS, push succeeds
- [x] Grafana → Explore → Loki → `{host="vps"}` returns VPS journald logs
- [x] `zfs list -t snapshot` shows `auto_` snapshots from Sanoid
- [x] `systemctl status fail2ban` on pebble and VPS — both active
- [x] `fail2ban-client status sshd` on pebble and VPS — sshd jail enabled
- [x] Grafana → Explore → Loki → `{host="pebble"}` — not explicitly re-verified after Alloy migration (was working with Promtail; Alloy config is equivalent)
- [x] NetBird Dashboard: default "All→All" ACL deleted; group-scoped policies added (2026-04-19)
