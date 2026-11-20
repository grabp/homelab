# Implementation Progress

## Current Stage: Phase 2 — Stage 14 (Immich)
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
| 7a | VPS Provisioning + NetBird Control Plane → **migrated to WireGuard** | ✅ COMPLETE | [docs/roadmap/stage-07a-vps-netbird.md](docs/roadmap/stage-07a-vps-netbird.md) |
| 7b | NetBird Homelab Client → **migrated to WireGuard hub-and-spoke** | ✅ COMPLETE | [docs/roadmap/stage-07b-netbird-client.md](docs/roadmap/stage-07b-netbird-client.md) |
| 7c | Identity Provider (Kanidm) | ✅ COMPLETE | [docs/roadmap/stage-07c-kanidm.md](docs/roadmap/stage-07c-kanidm.md) |
| 8 | Homepage Dashboard | ✅ COMPLETE | [docs/roadmap/stage-08-homepage.md](docs/roadmap/stage-08-homepage.md) |
| 9a | HA Services (Mosquitto + HACS + HA + Uptime Kuma) | ✅ COMPLETE | [docs/roadmap/stage-09a-ha-services.md](docs/roadmap/stage-09a-ha-services.md) |
| 9b | Voice Pipeline + ESPHome + Matter Server | ✅ COMPLETE | [docs/roadmap/stage-09b-voice-matter.md](docs/roadmap/stage-09b-voice-matter.md) |
| 10 | Hardening, Backups, VPS Log Shipping | ✅ COMPLETE | [docs/roadmap/stage-10-hardening-backups.md](docs/roadmap/stage-10-hardening-backups.md) |
| 10b | Pocket ID — NetBird Passkey IdP → **removed with NetBird** | ✅ COMPLETE | [docs/roadmap/stage-10b-pocket-id.md](docs/roadmap/stage-10b-pocket-id.md) |

---

## Phase 2: Machine 2 (boulder)

| Stage | Description | Status | Details |
|-------|-------------|--------|---------|
| 11 | Boulder Base System | ✅ COMPLETE | [docs/roadmap/stage-11-boulder-base.md](docs/roadmap/stage-11-boulder-base.md) |
| 12 | PostgreSQL Shared Instance | ✅ COMPLETE | [docs/roadmap/stage-12-postgresql.md](docs/roadmap/stage-12-postgresql.md) |
| 13 | Paperless-ngx + Stirling-PDF | ✅ COMPLETE | [docs/roadmap/stage-13-paperless.md](docs/roadmap/stage-13-paperless.md) |
| 14 | Immich | ⬜ NOT STARTED | [docs/roadmap/stage-14-immich.md](docs/roadmap/stage-14-immich.md) |
| 15 | Jellyfin | ⬜ NOT STARTED | [docs/roadmap/stage-15-jellyfin.md](docs/roadmap/stage-15-jellyfin.md) |
| 16 | Productivity (Outline, Vikunja, Karakeep, Actual) | ⬜ NOT STARTED | [docs/roadmap/stage-16-productivity.md](docs/roadmap/stage-16-productivity.md) |
| 16b | Calibre-Web Automated (e-book library) | ✅ COMPLETE | `homelab/calibre-web-automated/` — post-deploy: OIDC wiring in CWA admin UI |
| — | Zigbee2MQTT (pebble, replaces HA ZHA) | ✅ COMPLETE | `homelab/zigbee2mqtt/` — ZHA network resumed from ZBT-1 NVRAM (no re-pair needed), `https://zigbee.${domain}`. Post-deploy: rejoin remaining devices, delete ZHA integration, restore friendly names, rebuild groups/binds. See README Migration. |
| 17 | Windows VM | ⬜ NOT STARTED | [docs/roadmap/stage-17-windows-vm.md](docs/roadmap/stage-17-windows-vm.md) |
| 18 | Whisper Migration | ⬜ NOT STARTED | [docs/roadmap/stage-18-whisper-migration.md](docs/roadmap/stage-18-whisper-migration.md) |

---

## Maintenance: NixOS 26.05 upgrade — ✅ COMPLETE

`system.stateVersion` stays `"25.11"` on all hosts. Deploy order: vps → boulder → pebble. Snapshot Kanidm + Grafana state on pebble before deploying (one-way migrations).

Lessons from the 25.11 → 26.05 switch:
- **deploy-rs breaks on release upgrades** ([serokell/deploy-rs#390](https://github.com/serokell/deploy-rs/issues/390)): activation restarts sshd/journald/dbus, the SSH channel dies, magic rollback fails with `Could not acquire lock`. Use `nixos-rebuild switch|boot --flake path:.#<host> --target-host admin@<ip> --sudo` for release bumps; `just deploy` is fine afterwards.
- **dbus → dbus-broker** is the new default and needs a reboot (`switch` exits 4 with `Failed to reload dbus-broker.service`). Prefer `nixos-rebuild boot` + reboot.
- **Network is intercepted on port 53** (router/ISP — `id.server` gets no Cloudflare answer). At boot Pi-hole cached an upstream block (`0.0.0.0`, FTL status 8) for huggingface.co/grafana.com, which broke faster-whisper; `pihole reloaddns` cleared it. Check router DNS filtering.

| Step | Description | Status |
|------|-------------|--------|
| 1 | nixpkgs → nixos-26.05; Kanidm option renames (`server.enable`/`server.settings`), 1.9 kept via `permittedInsecurePackages`; Grafana `secret_key` from sops (`grafana/secret_key`, old default value); Caddy plugin hash; `nixfmt-rfc-style` → `nixfmt` | ✅ COMPLETE — deployed to vps, boulder, pebble (2026-11-20) |
| 2 | Kanidm 1.9 → 1.10 (pebble deploy, `kanidmd domain upgrade-check` first) | ✅ COMPLETE |
| 3 | Kanidm 1.10 → 1.11, drop `permittedInsecurePackages`; update ADR 0005, stage-07c, pattern 21 | ✅ COMPLETE |
| 3b | Kanidm 1.11 → 1.12 (1.11 deprecated, EOL 2026-12-01) | ✅ COMPLETE — 1.12.1, domain level 16 |
| 4 | Grafana secret_key rotation: stop Grafana, re-encrypt `grafana.db` with grafana-secretkey-rotation-tool, put new random key in sops, deploy | ✅ COMPLETE — rotated 2026-11-20 |

---

## Maintenance: container image updates (2026-11)

Pins are `tag@sha256:<linux/amd64 manifest digest>` (oci-digest skill). Deploy and verify each group before the next.

Lessons:
- **Pebble resolv.conf had only `127.0.0.1`**: openresolv drops non-local nameservers when a local one is listed (`resolv_conf_local_only` defaults to YES). Activation stops Pi-hole before pulling new images, so pulls failed with `no such host`. Fixed with `networking.resolvconf.extraConfig = "resolv_conf_local_only=NO"`. For Pi-hole image bumps, pre-pulling on pebble is still the safest option.
- **PostgreSQL collation mismatch after glibc 2.40 → 2.42** (26.05): `REINDEX DATABASE` + `ALTER DATABASE … REFRESH COLLATION VERSION` for every database on boulder. Repeat after any glibc bump that warns.
- **matterjs-server runs as UID 1000**; if the Python server ran again in between (rollback), re-`chown -R 1000:1000 /var/lib/matter-server` before retrying.

| Step | Images | Host | Status |
|------|--------|------|--------|
| 1 | oauth2-proxy v7.15.6, pihole 2026.11.0, esphome 2026.11.0, code-server 4.146.0, calibre-web-automated v4.0.8 (`latest` → version tags) | pebble, boulder | ✅ COMPLETE — deployed 2026-11-21 |
| 2 | stirling-pdf 0.42.0 → 3.4.0 (env vars renamed; old `/configs` moved aside) | boulder | ✅ COMPLETE — deployed 2026-11-21 |
| 3 | paperless-ngx 2.20.15 → 3.5.1 + redis 7 → 8 (`PAPERLESS_SECRET_KEY`, keep rejecting duplicates) | boulder | ✅ COMPLETE — deployed 2026-11-21 |
| 4 | python-matter-server → matterjs-server 1.6.0 (data migrated on first start, runs as UID 1000) | pebble | ✅ COMPLETE — deployed 2026-11-21 |
| 5 | home-assistant 2026.4.3 → 2026.11.2 (review breaking changes for used integrations first) | pebble | ⬜ NOT STARTED |

---

## Quick Commands

```bash
# Deploy pebble (homelab server)
just deploy pebble

# Deploy boulder (media/productivity server)
just deploy boulder

# Deploy VPS
just deploy-vps

# Provision boulder (first time only)
just gen-boulder-hostkey   # generate host key, print age key
# → edit .sops.yaml, then:
just rekey
just provision-boulder 192.168.10.51

# Check NetBird status
just netbird-status

# Edit secrets
just edit-secrets-pebble  # pebble secrets
just edit-secrets-boulder # boulder secrets
just edit-secrets-vps     # VPS secrets
```

---

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — High-level architecture decisions
- [docs/roadmap/](docs/roadmap/) — Implementation stages and plan
- [docs/patterns/index.md](docs/patterns/index.md) — Verified code patterns
- [docs/SERVICE-CONFIGS.md](docs/SERVICE-CONFIGS.md) — Per-service configuration notes
- [docs/STRUCTURE.md](docs/STRUCTURE.md) — Repository layout
- docs/roadmap/stage-*.md — Detailed stage completion notes
