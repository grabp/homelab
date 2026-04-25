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
| What's been implemented so far? | [PROGRESS.md](../PROGRESS.md) |
| What stage is next? | [roadmap/index.md](roadmap/index.md) |
| How do I add a new service? | [patterns/01-flake-with-deploy-disko-sops.md](patterns/01-flake-with-deploy-disko-sops.md) |
| How do I fix container firewall issues? | [patterns/19-netavark-firewall.md](patterns/19-netavark-firewall.md) |

## Documentation Sections

| Section | Purpose |
|---------|---------|
| [architecture/](architecture/) | System architecture, ADRs, auth, ports/DNS |
| [operations/](operations/) | Runbooks for deploy, secrets, backups, monitoring |
| [patterns/](patterns/) | Reusable NixOS patterns from NIX-PATTERNS.md |
| [roadmap/](roadmap/) | Per-stage implementation notes (1–18) |
| [archive/](archive/) | Archived research documents |

## Machine-Specific Docs

| Machine | Purpose |
|---------|---------|
| [machines/nixos/pebble/README.md](../machines/nixos/pebble/README.md) | Homelab server (primary services) |
| [machines/nixos/vps/README.md](../machines/nixos/vps/README.md) | VPS (NetBird control plane, Pocket ID) |

## Service READMEs

Each service has its own README in `homelab/<service>/README.md`:

- caddy, pihole, grafana, loki, prometheus
- vaultwarden, kanidm, homepage, uptime-kuma
- home-assistant, mosquitto, wyoming, matter-server, netbird
- backup
