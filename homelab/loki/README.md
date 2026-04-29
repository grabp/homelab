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

Enabling this module automatically enables `my.services.alloy` for local log
shipping (pebble → localhost). Remote machines (vps, boulder) enable
`my.services.alloy` independently — see `homelab/alloy/`.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 3100 | TCP | 0.0.0.0 | Loki HTTP API (push + query); firewall opens on `wt0` (VPS over NetBird) and `eth0` (boulder over LAN) |

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
- `http_listen_address = "0.0.0.0"` is intentional — Alloy on both VPS (NetBird
  `wt0`) and boulder (LAN `eth0`) push to pebble. Firewall opens port 3100 on
  both interfaces; see `pebble/default.nix`.

## Backup / restore

State: `/var/lib/loki/` — chunk data, index, compactor working dir.
Retention: 30 days (`limits_config.retention_period`).
Included in restic via `/var/lib` path. On restore, Loki rebuilds its index
from retained chunks automatically. Alloy WAL state is in `/var/lib/alloy/`
(see `homelab/alloy/README.md`).
