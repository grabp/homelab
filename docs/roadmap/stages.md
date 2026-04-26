---
kind: roadmap
title: Stage Summary
tags: [stages, roadmap]
---

# Stage Summary

This table provides a high-level overview of all implementation stages. For detailed narrative, implementation notes, and lessons learned, see the individual stage files linked below.

## Phase 1: Pebble (Homelab Server)

| Phase | Stage | Name | Host | Status |
|-------|-------|------|------|--------|
| 1 | 1 | Base System | pebble | ✅ COMPLETE |
| 1 | 2 | Secrets Management | pebble | ✅ COMPLETE |
| 1 | 3 | DNS (Pi-hole) | pebble | ✅ COMPLETE |
| 1 | 4 | Reverse Proxy (Caddy) | pebble | ✅ COMPLETE |
| 1 | 5 | Password Management (Vaultwarden) | pebble | ✅ COMPLETE |
| 1 | 6 | Monitoring (Prometheus + Grafana + Loki) | pebble | ✅ COMPLETE |
| 1 | 7a | VPS Provisioning + NetBird Control Plane | vps | ✅ COMPLETE |
| 1 | 7b | NetBird Homelab Client + Routes | pebble | ✅ COMPLETE |
| 1 | 7c | Identity Provider (Kanidm) | pebble | ✅ COMPLETE |
| 1 | 8 | Homepage Dashboard | pebble | ✅ COMPLETE |
| 1 | 9a | HA Services (Mosquitto + HACS + HA + Uptime Kuma) | pebble | ✅ COMPLETE |
| 1 | 9b | Voice Pipeline + ESPHome + Matter Server | pebble | ✅ COMPLETE |
| 1 | 10 | Hardening, Backups, VPS Log Shipping | pebble + vps | ✅ COMPLETE |
| 1 | 10b | Pocket ID — NetBird Passkey IdP | vps | ✅ COMPLETE |

## Phase 2: Boulder (Second Machine)

| Phase | Stage | Name | Host | Status |
|-------|-------|------|------|--------|
| 2 | 11 | Base System — Boulder Hardware | boulder | ☐ NOT STARTED |
| 2 | 12 | PostgreSQL Shared Instance | boulder | ☐ NOT STARTED |
| 2 | 13 | Paperless-ngx + Stirling-PDF | boulder | ☐ NOT STARTED |
| 2 | 14 | Immich Photo Management | boulder | ☐ NOT STARTED |
| 2 | 15 | Jellyfin Media Server | boulder | ☐ NOT STARTED |
| 2 | 16 | Productivity Apps | boulder | ☐ NOT STARTED |
| 2 | 17 | Windows VM — libvirt/QEMU | boulder | ☐ NOT STARTED |
| 2 | 18 | Whisper Migration | boulder | ☐ NOT STARTED |

---

**Individual stage files:** See [index.md](./index.md) for links to detailed implementation notes for each stage.
