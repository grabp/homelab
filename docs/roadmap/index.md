---
kind: navigation
title: Implementation Roadmap
---

# Implementation Roadmap

This directory contains the detailed implementation notes for each stage of the homelab build.

## Phase 1: Pebble (Homelab Server) — COMPLETE

| Stage | Name | Status | Link |
|-------|------|--------|------|
| 1 | Base System | ✅ COMPLETE | [stage-01-base-system.md](stage-01-base-system.md) |
| 2 | Secrets Management | ✅ COMPLETE | [stage-02-secrets.md](stage-02-secrets.md) |
| 3 | DNS (Pi-hole) | ✅ COMPLETE | [stage-03-dns.md](stage-03-dns.md) |
| 4 | Reverse Proxy (Caddy) | ✅ COMPLETE | [stage-04-caddy.md](stage-04-caddy.md) |
| 5 | Password Management (Vaultwarden) | ✅ COMPLETE | [stage-05-vaultwarden.md](stage-05-vaultwarden.md) |
| 6 | Monitoring (Prometheus + Grafana + Loki) | ✅ COMPLETE | [stage-06-monitoring.md](stage-06-monitoring.md) |
| 7a | VPS Provisioning + NetBird Control Plane | ✅ COMPLETE | [stage-07a-vps-netbird.md](stage-07a-vps-netbird.md) |
| 7b | NetBird Homelab Client + Routes | ✅ COMPLETE | [stage-07b-netbird-client.md](stage-07b-netbird-client.md) |
| 7c | Identity Provider (Kanidm) | ✅ COMPLETE | [stage-07c-kanidm.md](stage-07c-kanidm.md) |
| 8 | Homepage Dashboard | ✅ COMPLETE | [stage-08-homepage.md](stage-08-homepage.md) |
| 9a | HA Services (Mosquitto + HACS + HA + Uptime Kuma) | ✅ COMPLETE | [stage-09a-ha-services.md](stage-09a-ha-services.md) |
| 9b | Voice Pipeline + ESPHome + Matter Server | ✅ COMPLETE | [stage-09b-voice-matter.md](stage-09b-voice-matter.md) |
| 10 | Hardening, Backups, VPS Log Shipping | ✅ COMPLETE | [stage-10-hardening-backups.md](stage-10-hardening-backups.md) |
| 10b | Pocket ID — NetBird Passkey IdP | ✅ COMPLETE | [stage-10b-pocket-id.md](stage-10b-pocket-id.md) |

## Phase 2: Boulder (Second Machine) — NOT STARTED

| Stage | Name | Status | Link |
|-------|------|--------|------|
| 11 | Base System — Boulder Hardware | NOT STARTED | [stage-11-boulder-base.md](stage-11-boulder-base.md) |
| 12 | PostgreSQL Shared Instance | NOT STARTED | [stage-12-postgresql.md](stage-12-postgresql.md) |
| 13 | Paperless-ngx + Stirling-PDF | NOT STARTED | [stage-13-paperless.md](stage-13-paperless.md) |
| 14 | Immich Photo Management | NOT STARTED | [stage-14-immich.md](stage-14-immich.md) |
| 15 | Jellyfin Media Server | NOT STARTED | [stage-15-jellyfin.md](stage-15-jellyfin.md) |
| 16 | Productivity Apps | NOT STARTED | [stage-16-productivity.md](stage-16-productivity.md) |
| 17 | Windows VM — libvirt/QEMU | NOT STARTED | [stage-17-windows-vm.md](stage-17-windows-vm.md) |
| 18 | Whisper Migration | NOT STARTED | [stage-18-whisper-migration.md](stage-18-whisper-migration.md) |

---

See `PROGRESS.md` in the repository root for the current status summary.
