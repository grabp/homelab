---
service: paperless
stage: 13
machine: boulder
status: active
---

# Paperless-ngx

## Purpose

Document management system running on boulder. Ingests PDFs and images placed in the consumption directory, runs Tesseract OCR (Polish + English), and makes them searchable through a web UI with tagging and full-text search.

Proxied by Caddy on pebble. DNS wildcard resolves `*.grab-lab.gg` to pebble; Caddy forwards to boulder's LAN IP.

## Ports

| Port | Interface | Service |
|------|-----------|---------|
| 8010 | 0.0.0.0 (firewall: eth0 only) | Paperless-ngx web UI |

Only reachable from pebble (LAN). Caddy on pebble terminates TLS and proxies inbound HTTPS.

## Secrets

| Key | File | Format | Purpose |
|-----|------|--------|---------|
| `paperless/admin_password` | `secrets/boulder.yaml` | plain password | Paperless `admin` superuser initial password |

Add via `just edit-secrets-boulder`.

The PostgreSQL `paperless` database user uses Unix socket peer authentication — no database password is needed.

## Depends on

- **Stage 11** — boulder base system (Netbird, alloy, node-exporter)
- **Stage 12** — shared PostgreSQL instance (`paperless` database + `paperless` user pre-created)

## Storage

Documents are stored on boulder's local ZFS pool under `/var/lib/paperless/`:

| Path | Contents |
|------|----------|
| `/var/lib/paperless/media` | Processed documents (auto-managed by Paperless) |
| `/var/lib/paperless/consume` | Drop zone for new documents (watch this dir) |
| `/var/lib/paperless/data` | Index, thumbnails, SQLite (superseded by PostgreSQL) |

These paths are covered by boulder's restic backup (default `paths = [ "/var/lib" ]`).

To drop documents for ingestion: `scp doc.pdf boulder:/var/lib/paperless/consume/`

**Why not NAS?** Synology DSM enables Windows/extended ACLs on shared folders by default. These override Unix mode bits server-side and deny NFS access to UIDs unknown to the NAS (e.g., the `paperless` system user, UID 315) even on `777` directories. Local ZFS + restic avoids this entirely.

## Known Gotchas

**First run admin password**: The `passwordFile` creates the `admin` superuser only on the first migration. Changing the file after first run does not change the password; use `paperless-manage changepassword admin` instead.

**PrivateNetwork**: Using `database.createLocally = false` (default) ensures all four paperless systemd units run with `PrivateNetwork = false`. This is required both for `paperless-web` to bind on `0.0.0.0:8010` and for all units to reach the PostgreSQL Unix socket at `/run/postgresql`.

## Backup / Restore

**State locations:**
- `/var/lib/paperless` — all document files, thumbnails, data — covered by boulder restic
- PostgreSQL `paperless` database — daily dumps at `/var/backup/postgresql/paperless.sql.zst` via Stage 12 `postgresqlBackup`

**Restore:**
1. Restore `/var/lib/paperless` from the boulder restic repository.
2. Restore the PostgreSQL dump: `zstd -d paperless.sql.zst | psql -U paperless paperless`.
3. Run `systemctl restart paperless-scheduler` to re-index if needed.
