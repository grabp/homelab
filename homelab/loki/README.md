---
service: loki
stage: 6
machine: pebble
status: deployed
---

# Loki

## Purpose

Log aggregation backend. Receives logs from Alloy (journald → Loki push) and
exposes them to Grafana via the Loki datasource. Includes a Loki ruler with
security alert rules (SSH brute-force, root login, sudo failures) forwarded to
Alertmanager.

Co-located in this module: **Alloy** log shipper (replaces EOL Promtail).

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 3100 | TCP | 0.0.0.0 | Loki HTTP API (push + query); also reachable over NetBird for VPS log shipping |

## Secrets

None — Loki runs without authentication (`auth_enabled = false`) in single-tenant mode.

## Depends on

- Nothing (standalone; Grafana depends on Loki, not the reverse)
- Alertmanager (part of `my.services.prometheus` module) — ruler pushes alerts to port 9093

## DNS

Not directly exposed via Caddy. Grafana accesses it at `http://localhost:3100`.

## OIDC

Not applicable.

## Known gotchas

- Package is `pkgs.grafana-loki` (not `pkgs.loki`).
- `compactor.delete_request_store = "filesystem"` is **required** when
  `retention_enabled = true` — Loki rejects the config otherwise.
- `boltdb-shipper` is deprecated; this module uses `tsdb` (schema v13).
- `http_listen_address = "0.0.0.0"` is intentional — allows VPS log shipping
  over the NetBird mesh (firewall restricts to `wt0` interface).
- Alloy uses River/Alloy syntax (`.alloy` files), not YAML. Config written to
  `/etc/alloy/config.alloy` via `environment.etc`.
- Promtail is EOL as of 2026-03-02 — do not add new Promtail instances.

## Backup / restore

State: `/var/lib/loki/` — chunk data, index, compactor working dir.
Retention: 30 days (configured via `limits_config.retention_period`).
Included in restic via `/var/lib` path. On restore, Loki rebuilds its index
from retained chunks automatically.
