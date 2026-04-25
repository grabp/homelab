---
service: uptime-kuma
stage: 9a
machine: pebble
status: deployed
---

# Uptime Kuma

## Purpose

Service availability monitor. Tracks HTTP/TCP/DNS uptime for all homelab
services and sends alerts when services go down. Web UI at `uptime.grab-lab.gg`.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 3001 | TCP | localhost | Web UI + WebSocket (proxied by Caddy → `uptime.grab-lab.gg`) |

## Secrets

None — Uptime Kuma manages its own admin account internally via the web UI
(set up admin password on first visit).

## Depends on

- Caddy (TLS termination)

## DNS

`uptime.grab-lab.gg` → Caddy wildcard vhost → `localhost:3001`.

## OIDC

Not supported natively. Access control relies on Uptime Kuma's own login.
Optional: add Caddy `forward_auth` via Kanidm (NIX-PATTERNS.md Pattern 22)
as an additional layer.

## Known gotchas

- `HOST = "127.0.0.1"` binds to localhost only — Caddy handles public access.
- Settings are passed as environment variables (`PORT`, `HOST`).
- Module description notes "this assumes a reverse proxy to be set" — do not
  expose port 3001 directly.
- Monitors and notification channels are configured exclusively via the web UI
  (not declarative).

## Backup / restore

State: `/var/lib/uptime-kuma/` — SQLite database with all monitor configs and
status history. Included in restic via `/var/lib` path. On restore, all
monitors and notification channels are recovered from the database.
