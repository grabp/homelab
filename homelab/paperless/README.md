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

## Design

Two OCI containers on a shared Podman network (`paperless-net`):

| Container | Image | Role |
|-----------|-------|------|
| `paperless` | `ghcr.io/paperless-ngx/paperless-ngx:2.20.15` | Web UI + workers |
| `paperless-redis` | `docker.io/library/redis:7-alpine` | Celery task broker |

PostgreSQL is not in a container — it runs as a NixOS service on the host. The `paperless` container mounts `/run/postgresql` to access the Unix socket directly.

## Ports

| Port | Interface | Service |
|------|-----------|---------|
| 8010 | 0.0.0.0 (firewall: eth0 only) | Paperless-ngx web UI |

Only reachable from pebble (LAN). Caddy on pebble terminates TLS and proxies inbound HTTPS.

## Secrets

| Key | File | Format | Purpose |
|-----|------|--------|---------|
| `paperless/admin_password` | `secrets/boulder.yaml` | env file (`PAPERLESS_ADMIN_PASSWORD=<pw>`) | Paperless `admin` superuser initial password |

**Format**: The value must be in env-file format, not a plain password:
```yaml
paperless/admin_password: "PAPERLESS_ADMIN_PASSWORD=your-password-here"
```

Add via `just edit-secrets-boulder`.

The PostgreSQL `paperless` database user uses Unix socket trust authentication — no database password is needed.

## Depends on

- **Stage 11** — boulder base system (Netbird, alloy, node-exporter)
- **Stage 12** — shared PostgreSQL instance (`paperless` database + `paperless` user pre-created)

## Storage

Documents are stored on boulder's local ZFS pool under `/var/lib/paperless/`:

| Path | Contents |
|------|----------|
| `/var/lib/paperless/media` | Processed documents (auto-managed by Paperless) |
| `/var/lib/paperless/consume` | Drop zone for new documents |
| `/var/lib/paperless/data` | Index, thumbnails, SQLite cache |
| `/var/lib/paperless-redis` | Redis persistence (RDB snapshots) |

Container UID is 1000 — all `/var/lib/paperless` paths must be owned by `1000:1000`.

These paths are covered by boulder's restic backup (default `paths = [ "/var/lib" ]`).

To drop documents for ingestion: `scp doc.pdf boulder:/var/lib/paperless/consume/`

**Why not NAS?** Synology DSM enables Windows/extended ACLs on shared folders by default. These override Unix mode bits server-side and deny NFS access to UIDs unknown to the NAS (e.g., the `paperless` system user) even on `777` directories. Local ZFS + restic avoids this entirely.

## PostgreSQL Auth

The PostgreSQL module (`homelab/postgresql/default.nix`) adds:
```
local paperless paperless trust
```
before the default peer catch-all. This allows the container's internal UID (1000) to authenticate as the `paperless` PostgreSQL user via Unix socket without a password — peer UID check is bypassed with `trust`. Only the paperless container mounts the socket, so the blast radius is limited.

## Known Gotchas

**First run admin password**: The `PAPERLESS_ADMIN_PASSWORD` env var creates the `admin` superuser only on the first migration. Changing the env var after first run does not change the password; use `paperless-manage changepassword admin` instead.

**Polish OCR language**: `PAPERLESS_OCR_LANGUAGES=pol` installs the Polish Tesseract language pack at container startup. This requires the container to run as root, which NixOS rootful Podman does by default.

**OCR errors on complex PDFs**: Two flags in `PAPERLESS_OCR_USER_ARGS` handle known failures:
- `continue_on_soft_render_error: true` — Ghostscript soft errors during PDF/A conversion no longer abort OCR
- `optimize: 0` — disables JPEG transcoding in ocrmypdf (avoids `transcode_jpegs` failures on complex datasheets)

**Pattern 19 (Netavark firewall)**: Both containers depend on `firewall.service` via `partOf` so their Netavark DNAT port rules are re-registered after NixOS firewall reloads.

**UID migration**: If migrating from the native `services.paperless` module (which used UID 315), run:
```bash
sudo systemctl stop paperless-scheduler paperless-consumer paperless-web paperless-task-queue
sudo chown -R 1000:1000 /var/lib/paperless
```

## Backup / Restore

**State locations:**
- `/var/lib/paperless` — all document files, thumbnails, data — covered by boulder restic
- `/var/lib/paperless-redis` — Redis snapshots (ephemeral task state, not critical)
- PostgreSQL `paperless` database — daily dumps at `/var/backup/postgresql/paperless.sql.zst`

**Restore:**
1. Restore `/var/lib/paperless` from boulder restic repository. Ensure ownership is `1000:1000`.
2. Restore the PostgreSQL dump: `zstd -d paperless.sql.zst | psql -U paperless paperless`.
3. Start services: `systemctl restart podman-paperless-redis podman-paperless`.
