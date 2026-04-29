---
service: postgresql
stage: 12
machine: boulder
status: deployed
---

# PostgreSQL

## Purpose

Shared PostgreSQL 17 instance on boulder. Provides a single managed database
server for all boulder services that require relational storage: Outline (wiki),
Vikunja (tasks), and Paperless-ngx (document management).

## Databases

| Database | Owner user | Used by |
|----------|------------|---------|
| `outline` | `outline` | Stage 16 — Outline wiki |
| `vikunja` | `vikunja` | Stage 16 — Vikunja task manager |
| `paperless` | `paperless` | Stage 13 — Paperless-ngx |

Users and databases are created idempotently via `ensureDatabases` /
`ensureUsers` — never deleted by NixOS if removed from config.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 5432 | TCP | localhost only | PostgreSQL wire protocol |

`enableTCPIP` is not set — only Unix socket connections are accepted. Each
service must run as (or connect as) its matching database user via peer auth,
or be granted password auth in a future stage if needed.

## Secrets

No sops secrets at this stage. `ensureUsers` provisions accounts via peer
authentication (Unix socket). Services that need password auth over TCP should
declare a sops secret and set it via a post-start script or `initialScript`.

## Depends on

- Stage 11 boulder base system

## Known gotchas

- Default package on `stateVersion = "25.11"` is `postgresql_17`. Changing the
  major version after data dir initialisation requires a manual `pg_upgrade`.
- `ensureDatabases` / `ensureUsers` are **additive only** — removing a name
  from the list does not drop the database or role; do that manually with
  `sudo -u postgres psql`.
- `ensureDBOwnership = true` requires the same name to appear in both
  `ensureDatabases` and the `ensureUsers` entry — enforced by a NixOS assertion.

## Backup / restore

`services.postgresqlBackup` runs `pg_dump` per-database via a daily systemd
timer. Compressed dumps are written to `/var/backup/postgresql/`:

| File | Contents |
|------|----------|
| `outline.sql.zst` | Outline database dump |
| `vikunja.sql.zst` | Vikunja database dump |
| `paperless.sql.zst` | Paperless-ngx database dump |

Files are owned by `postgres`, mode `0600` (umask 0077).

**Future:** The `homelab/backup` module backs up `/var/backup` (covers all
service dumps). When boulder enables that module (future backup stage), postgresql
dumps will be included automatically — no path change needed.

### Restore a database

```bash
# Decompress and restore a single database
zstd -d /var/backup/postgresql/outline.sql.zst -o /tmp/outline.sql
sudo -u postgres psql outline < /tmp/outline.sql
```
