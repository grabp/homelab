---
service: stirling-pdf
stage: 13
machine: boulder
status: active
---

# Stirling-PDF

## Purpose

Stateless PDF toolkit running as an OCI container on boulder. Provides a web UI for PDF operations: merge, split, compress, convert, rotate, watermark, and more. No accounts or persistent document storage — files are processed in-memory and returned to the browser.

Proxied by Caddy on pebble. DNS wildcard resolves `*.grab-lab.gg` to pebble; Caddy forwards to boulder's LAN IP.

## Ports

| Port | Interface | Service |
|------|-----------|---------|
| 8080 | 0.0.0.0 (firewall: eth0 only) | Stirling-PDF web UI |

Only reachable from pebble (LAN). Caddy on pebble terminates TLS and proxies inbound HTTPS.

## Secrets

None. Stirling-PDF is stateless and requires no credentials.

## Depends on

- **Stage 11** — boulder base system (networking, firewall)
- **Caddy on pebble** — TLS termination and reverse proxy (Stage 4)

## Known Gotchas

**Image pinned to amd64 digest**: The image reference includes `@sha256:...` for the linux/amd64 manifest of v0.42.0. Update with the `/oci-digest` skill when bumping versions.

**Pattern 19 (Netavark/firewall ordering)**: The `podman-stirling-pdf` systemd service declares `partOf = [ "firewall.service" ]` so Podman re-registers its DNAT rules whenever the NixOS firewall reloads. Without this, the container becomes unreachable after any firewall change.

**Caddy option reference**: `homelab/caddy/default.nix` references `config.my.services.stirlingPdf.port`. This option is defined in this module and always available (returns default 8080) even when the service is disabled on pebble — this is intentional and harmless.

## Backup / Restore

Stirling-PDF is fully stateless. `/var/lib/stirling-pdf` holds only optional configuration overrides; if lost, the container restarts with defaults. No restore procedure needed.
