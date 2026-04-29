---
service: node-exporter
stage: 11
machine: pebble, boulder
status: deployed
---

# Node Exporter

## Purpose

Prometheus node exporter. Exposes host-level metrics (CPU, memory, disk, network,
systemd unit states) for scraping by pebble's Prometheus instance.

Used by two modules:

| Caller | `openFirewall` | Listen address | Scraped by |
|--------|---------------|----------------|------------|
| `my.services.prometheus` (pebble) | `false` | `0.0.0.0` | Prometheus at `localhost:9100` |
| `my.services.nodeExporter` (boulder) | `true` (default) | `0.0.0.0` | Prometheus at `192.168.10.51:9100` |

Pebble relies on the firewall (port 9100 not opened) to prevent external access.
Boulder opens port 9100 on the LAN so pebble can scrape it remotely.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 9100 | TCP | localhost (pebble) / LAN (boulder) | Prometheus metrics endpoint |

## Secrets

None.

## Depends on

- `my.services.prometheus` on pebble — scrape targets defined in
  `homelab/prometheus/default.nix` (pebble: `job_name = "node"`) and
  `machines/nixos/pebble/default.nix` (boulder: `job_name = "node_boulder"`)

## DNS

Not applicable.

## OIDC

Not applicable.

## Known gotchas

- `listenAddress = "0.0.0.0"` always — access control is via firewall, not bind
  address. `openFirewall = false` keeps port 9100 closed to the network.
- The `systemd` collector is enabled on all instances — required for the
  `SystemdServiceFailed` Prometheus alert rule.
- Duplicate `job_name` values in `scrapeConfigs` cause Prometheus config
  validation to fail at build time. Boulder uses `job_name = "node_boulder"` to
  avoid colliding with pebble's `job_name = "node"`.

## Backup / restore

Stateless — no persistent data. Metrics history lives in Prometheus TSDB.
