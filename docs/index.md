---
kind: index
title: Homelab Documentation
---

# Homelab Documentation

Find answers quickly with the Q→Doc lookup table below.

## Quick Reference

| Question | Document |
|----------|----------|
| How is this repo organized? | [STRUCTURE.md](STRUCTURE.md) |
| What's the overall system architecture? | [ARCHITECTURE.md](ARCHITECTURE.md) |
| How do authentication and SSO work? | [architecture/auth.md](architecture/auth.md) |
| What services run on which ports? | [architecture/ports-and-dns.md](architecture/ports-and-dns.md) |
| How do I deploy changes? | [operations/deploy.md](operations/deploy.md) |
| How do I add or rotate secrets? | [operations/secrets.md](operations/secrets.md) |
| How do backups work? | [operations/backup-and-restore.md](operations/backup-and-restore.md) |
| How do I access monitoring dashboards? | [operations/monitoring.md](operations/monitoring.md) |
| What's been implemented so far? | See PROGRESS.md in repo root |
| What stage is next? | [roadmap/index.md](roadmap/index.md) |
| How do I add a new service? | [patterns/01-flake-with-deploy-disko-sops.md](patterns/01-flake-with-deploy-disko-sops.md) |
| How are systemd dependencies managed? | [patterns/16-systemd-dependencies.md](patterns/16-systemd-dependencies.md) |

## Documentation Sections

| Section | Purpose |
|---------|---------|
| [architecture/](architecture/overview.md) | System architecture, ADRs, auth, ports/DNS |
| [operations/](operations/deploy.md) | Runbooks for deploy, secrets, backups, monitoring |
| [patterns/](patterns/index.md) | Reusable NixOS patterns from NIX-PATTERNS.md |
| [roadmap/](roadmap/index.md) | Per-stage implementation notes (1–18) |
| [archive/](archive/ha-companion-services-research.md) | Archived research documents |

## Machine-Specific Docs

| Machine | Purpose | README |
|---------|---------|--------|
| pebble | Homelab server (primary services) | See `machines/nixos/pebble/README.md` in repo |
| vps | VPS (NetBird control plane, Pocket ID) | See `machines/nixos/vps/README.md` in repo |

## Service Documentation

Each service has its own README co-located with its module in `homelab/<service>/README.md`. These are not included in the docs site but are available in the repository:

- caddy, pihole, grafana, loki, prometheus
- vaultwarden, kanidm, homepage, uptime-kuma
- home-assistant, mosquitto, wyoming, matter-server, netbird
- backup
