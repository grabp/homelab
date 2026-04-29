---
kind: roadmap
stage: 12
title: PostgreSQL Shared Instance
status: complete
---

# Stage 12: PostgreSQL Shared Instance

## Status
COMPLETE

## What Gets Built
Single PostgreSQL server for Outline, Vikunja, and Paperless-ngx. Each service gets its own database and user. Daily logical dumps via `services.postgresqlBackup` are written to `/var/backup/postgresql/` and picked up automatically by the boulder restic job.

## Key Files
- `homelab/postgresql/default.nix` — PostgreSQL instance + postgresqlBackup dumps
- `homelab/postgresql/README.md` — backup/restore procedures
- `machines/nixos/boulder/default.nix` — enables `my.services.postgresql`

## Dependencies
- Stage 11 (base system)
- Stage 10 backup module enabled on boulder (for restic to pick up `/var/backup`)

## Configuration Notes
- `services.postgresqlBackup` produces per-database `.sql.zstd` dumps daily
- Dumps land in `/var/backup/postgresql/`, owned by `postgres:postgres`, mode `0600`
- Previous dump kept as `.prev.sql.zstd` (one rotation)
- Backup module default paths (`/var/lib`, `/var/backup`) cover postgresql dumps without additional config

## Verification Steps
- [x] `systemctl status postgresql` shows active
- [x] `psql -U postgres -l` lists databases
- [x] Databases created: `outline`, `vikunja`, `paperless`
- [x] Each database user has ownership of its database
- [x] `systemctl start postgresqlBackup-outline.service` produces dump in `/var/backup/postgresql/`
- [x] Restic snapshot on boulder includes `/var/backup/postgresql/` files
