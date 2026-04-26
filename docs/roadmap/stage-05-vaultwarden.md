---
kind: roadmap
stage: 5
title: Password Vault with Vaultwarden
status: complete
---

# Stage 5: Password Management (Vaultwarden)

## Status
COMPLETE (2026-04-13)

## Files Created
- `homelab/vaultwarden/default.nix` — Vaultwarden module: native service, SQLite backend, automatic daily backups

## Files Modified
- `homelab/default.nix` — enabled `./vaultwarden` import
- `homelab/caddy/default.nix` — added `vault.grab-lab.gg` reverse proxy
- `machines/nixos/pebble/default.nix` — `my.services.vaultwarden.enable = true`; fixed stage number comments

## Configuration Notes
- Native `services.vaultwarden` module (~50 MB RAM, negligible CPU)
- Port 8222/tcp (remapped from default 8000/8080 for clarity)
- SQLite database at `/var/lib/bitwarden_rs/db.sqlite3` (default)
- `backupDir = "/var/backup/vaultwarden"` creates automatic daily SQLite backups
- `SIGNUPS_ALLOWED = false` after initial account creation (still allows invitations)
- `DOMAIN = "https://vault.grab-lab.gg"` required for mobile apps and browser extensions
- Admin panel at `/admin` requires `ADMIN_TOKEN` from sops secret

## Pre-Deploy Action Required
```bash
# Generate admin token
ADMIN_TOKEN=$(openssl rand -base64 48)

# Add to secrets file
just edit-secrets
# Add entry:
# vaultwarden/admin_token: |
#   ADMIN_TOKEN=<paste-generated-token-here>
```

## Post-Setup Actions Taken
- `SIGNUPS_ALLOWED` flipped to `false` in `homelab/vaultwarden/default.nix` after account creation
- UniFi DHCP corrected: removed `1.1.1.1` as secondary DNS, Pi-hole only (`192.168.10.50`). iOS (and most modern OSes) query all configured DNS servers in parallel and accept the first response — a public fallback causes split-DNS domains to fail intermittently because the public server returns NXDOMAIN faster than Pi-hole returns the correct IP.

## Verification (All Passed 2026-04-14)
- [x] `curl https://vault.grab-lab.gg` returns HTTP 200
- [x] Create an account at `https://vault.grab-lab.gg`
- [x] Store a password, verify retrieval
- [x] Mobile app (Bitwarden) connects to `https://vault.grab-lab.gg` as custom server
- [x] Browser extension works with vault
- [x] `ls /var/backup/vaultwarden` shows daily SQLite backups
- [x] Admin panel accessible at `https://vault.grab-lab.gg/admin` with token
