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

Data lives in `/var/lib/postgresql/`. Include this path in the boulder restic
job (Stage 10 backup module) once it is enabled on boulder.

For a consistent dump-based backup, add a pre-backup script:

```bash
sudo -u postgres pg_dumpall > /var/backup/postgresql/dump.sql
```
