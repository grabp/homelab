---
service: calibre-web-automated
stage: 16
machine: boulder
status: active
---

# Calibre-Web Automated

## Purpose

Self-hosted e-book library running on boulder. Drop books into the ingest folder and they are automatically imported, converted to a target format (EPUB/MOBI/AZW3/KEPUB), and made searchable through a Calibre-Web UI. Includes KOReader sync, Hardcover metadata enrichment, and OIDC SSO via Kanidm.

Proxied by Caddy on pebble. DNS wildcard resolves `*.grab-lab.gg` to pebble; Caddy forwards to boulder's LAN IP.

## Ports

| Port | Interface | Service |
|------|-----------|---------|
| 8083 | 0.0.0.0 (firewall: eth0 only) | Calibre-Web Automated UI |

Only reachable from pebble (LAN). Caddy on pebble terminates TLS and proxies inbound HTTPS.

## Secrets

| Key | File | Format | Purpose |
|-----|------|--------|---------|
| `calibre-web-automated/hardcover_token` | `secrets/boulder.yaml` | env file (`HARDCOVER_TOKEN=<key>`) | Hardcover.app metadata API key |
| `kanidm/calibre_web_client_secret` | `secrets/pebble.yaml` | plain secret | Kanidm OAuth2 client credential |

**Hardcover format**: value must be in env-file format, not a raw key:
```yaml
calibre-web-automated/hardcover_token: "HARDCOVER_TOKEN=your-api-key-here"
```

Add via `just edit-secrets-boulder` and `just edit-secrets-pebble`.

## Depends on

- **Stage 11** — boulder base system (Netbird, alloy, node-exporter)
- **Stage 7c** — Kanidm (for OIDC SSO)

## Storage

All state on boulder's ZFS pool under `/var/lib/calibre-web-automated/`:

| Path | Contents |
|------|----------|
| `/var/lib/calibre-web-automated/config` | App DB (`app.db`), logs, settings |
| `/var/lib/calibre-web-automated/ingest` | Drop zone — files **deleted** after import |
| `/var/lib/calibre-web-automated/library` | Calibre library (`metadata.db` + book files) |

Container UID is 1000 — all paths must be owned by `1000:1000`.

These paths are covered by boulder's restic backup (default `paths = [ "/var/lib" ]`).

To drop books for ingestion: `scp book.epub boulder:/var/lib/calibre-web-automated/ingest/`

**Warning**: Files in the ingest folder are permanently deleted after processing. Never put your only copy there — download completely and verify before transferring.

## Post-Deploy OIDC Setup (Manual — CWA Admin UI)

CWA does not support env-var OIDC configuration. After first deploy:

1. Browse to `https://books.grab-lab.gg` → log in as `admin` / `admin123`
2. **Change the admin password immediately** (Admin Panel → Change Password)
3. Admin Panel → Basic Configuration → Feature Configuration:
   - Enable **Allow OAuth registration**
4. Admin Panel → Basic Configuration → OAuth Settings → Add Generic Provider:
   - **Metadata URL**: `https://id.grab-lab.gg/oauth2/openid/calibre-web/.well-known/openid-configuration`
   - **Client ID**: `calibre-web`
   - **Client Secret**: value from `kanidm/calibre_web_client_secret` (run `just edit-secrets-pebble` to view)
   - **Scopes**: `openid profile email`
   - **OAuth Redirect Host**: `https://books.grab-lab.gg`
5. Map JWT fields: username → `preferred_username`, email → `email`

## Known Gotchas

**Ingest deletes originals**: Files placed in `/cwa-book-ingest` are permanently removed after processing. Always keep a backup copy before ingesting.

**TRUSTED_PROXY_COUNT=1**: Required when running behind Caddy. Without it, CWA sees the wrong client IP and triggers "Session protection" errors on every request.

**Default credentials**: `admin`/`admin123` — change immediately after first login.

**Pattern 19 (Netavark firewall)**: The container depends on `firewall.service` via `partOf` so Netavark DNAT port rules are re-registered after NixOS firewall reloads.

**OIDC is UI-only**: Unlike Grafana, CWA has no env-var or config-file OIDC support. The Kanidm OAuth2 client is provisioned declaratively in Nix, but the CWA side must be configured through the admin panel (see post-deploy steps above).

## Backup / Restore

**State locations:**
- `/var/lib/calibre-web-automated` — all book files, library DB, config — covered by boulder restic

**Restore:**
1. Restore `/var/lib/calibre-web-automated` from boulder restic repository. Ensure ownership is `1000:1000`.
2. Start service: `systemctl restart podman-calibre-web-automated`.
3. Re-apply OIDC settings in the admin UI (stored in `app.db`, which is restored with the config volume).
