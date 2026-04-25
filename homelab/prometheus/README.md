---
service: prometheus
stage: 6
machine: pebble
status: deployed
---

# Prometheus

## Purpose

Metrics collection and alerting. Scrapes node exporter (host metrics) and
blackbox exporter (TLS/HTTP probes for all public service endpoints). Alerting
rules cover TLS cert expiry and failed systemd units. Alerts routed to
Alertmanager → Telegram.

Co-located in this module: **Alertmanager** (port 9093) and **Blackbox exporter** (port 9115).

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 9090 | TCP | localhost | Prometheus HTTP API (proxied by Caddy → `prometheus.grab-lab.gg`) |
| 9093 | TCP | localhost | Alertmanager HTTP API |
| 9115 | TCP | localhost | Blackbox exporter |
| 9100 | TCP | localhost | Node exporter (auto-assigned by module) |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `alertmanager/telegram_env` | `TELEGRAM_CHAT_ID=<id>\nTELEGRAM_BOT_TOKEN=<token>` | Telegram alert notifications |

## Depends on

- Loki (Alertmanager URL referenced in Loki ruler config at `http://127.0.0.1:9093`)

## DNS

`prometheus.grab-lab.gg` → Caddy wildcard vhost → `localhost:9090`.

## OIDC

Not applicable — Prometheus has no native auth. Access is via Caddy reverse
proxy (consider adding `forward_auth` via Kanidm if external access is needed).

## Known gotchas

- `listenAddress = "127.0.0.1"` to bind localhost only — Caddy handles public access.
- Blackbox exporter probes `*.grab-lab.gg` endpoints for TLS cert validity;
  requires Pi-hole split DNS to be up.
- `checkConfig = false` on Alertmanager — needed because env var substitution
  (`$TELEGRAM_CHAT_ID`) is not valid YAML during Nix eval time.
- Data retention: 30 days (`retentionTime = "30d"`). `/var/lib/prometheus2/`
  can grow large — monitor disk usage.

## Backup / restore

State: `/var/lib/prometheus2/` — TSDB data files.
Included in restic via `/var/lib` path. Metrics data is ephemeral by nature;
only the last 30 days is retained. Alertmanager state: `/var/lib/alertmanager/`.
