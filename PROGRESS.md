# Implementation Progress

## Current Stage: Phase 2 — Stage 11 (boulder base system)
## Status: NOT STARTED

---

## Completed Stages

| Stage | Description | Status | Details |
|-------|-------------|--------|---------|
| 1 | Base System | ✅ COMPLETE | [docs/roadmap/stage-01-base-system.md](docs/roadmap/stage-01-base-system.md) |
| 2 | Secrets Management | ✅ COMPLETE | [docs/roadmap/stage-02-secrets.md](docs/roadmap/stage-02-secrets.md) |
| 3 | DNS (Pi-hole) | ✅ COMPLETE | [docs/roadmap/stage-03-dns.md](docs/roadmap/stage-03-dns.md) |
| 4 | Reverse Proxy (Caddy) | ✅ COMPLETE | [docs/roadmap/stage-04-caddy.md](docs/roadmap/stage-04-caddy.md) |
| 5 | Password Management (Vaultwarden) | ✅ COMPLETE | [docs/roadmap/stage-05-vaultwarden.md](docs/roadmap/stage-05-vaultwarden.md) |
| 6 | Monitoring (Prometheus + Grafana + Loki) | ✅ COMPLETE | [docs/roadmap/stage-06-monitoring.md](docs/roadmap/stage-06-monitoring.md) |
| 7a | VPS Provisioning + NetBird Control Plane | ✅ COMPLETE | [docs/roadmap/stage-07a-vps-netbird.md](docs/roadmap/stage-07a-vps-netbird.md) |
| 7b | NetBird Homelab Client + Routes | ✅ COMPLETE | [docs/roadmap/stage-07b-netbird-client.md](docs/roadmap/stage-07b-netbird-client.md) |
| 7c | Identity Provider (Kanidm) | ✅ COMPLETE | [docs/roadmap/stage-07c-kanidm.md](docs/roadmap/stage-07c-kanidm.md) |
| 8 | Homepage Dashboard | ✅ COMPLETE | [docs/roadmap/stage-08-homepage.md](docs/roadmap/stage-08-homepage.md) |
| 9a | HA Services (Mosquitto + HACS + HA + Uptime Kuma) | ✅ COMPLETE | [docs/roadmap/stage-09a-ha-services.md](docs/roadmap/stage-09a-ha-services.md) |
| 9b | Voice Pipeline + ESPHome + Matter Server | ✅ COMPLETE | [docs/roadmap/stage-09b-voice-matter.md](docs/roadmap/stage-09b-voice-matter.md) |
| 10 | Hardening, Backups, VPS Log Shipping | ✅ COMPLETE | [docs/roadmap/stage-10-hardening-backups.md](docs/roadmap/stage-10-hardening-backups.md) |
| 10b | Pocket ID — NetBird Passkey IdP | ✅ COMPLETE | [docs/roadmap/stage-10b-pocket-id.md](docs/roadmap/stage-10b-pocket-id.md) |

---

## Phase 2: Machine 2 (boulder)

See [docs/roadmap/](docs/roadmap/) for Stages 11-18.

---

## Quick Commands

```bash
# Deploy pebble (homelab server)
just deploy pebble

# Deploy VPS
just deploy-vps

# Check NetBird status
just netbird-status

# Edit secrets
just edit-secrets        # homelab secrets
just edit-secrets-vps    # VPS secrets
```

---

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — High-level architecture decisions
- [docs/roadmap/](docs/roadmap/) — Implementation stages and plan
- [docs/patterns/index.md](docs/patterns/index.md) — Verified code patterns
- [docs/SERVICE-CONFIGS.md](docs/SERVICE-CONFIGS.md) — Per-service configuration notes
- [docs/STRUCTURE.md](docs/STRUCTURE.md) — Repository layout
- docs/roadmap/stage-*.md — Detailed stage completion notes
