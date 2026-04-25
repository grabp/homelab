---
kind: roadmap
stage: 6
title: Monitoring Stack
status: complete
---

# Stage 6: Monitoring (Prometheus + Grafana + Loki)

## Status
COMPLETE (verified 2026-04-14)

## Files Created
- `homelab/prometheus/default.nix` — Prometheus on `127.0.0.1:9090`, node exporter (`:9100`, systemd collector), 30d retention
- `homelab/grafana/default.nix` — Grafana on `127.0.0.1:3000`, declarative Prometheus + Loki datasources, admin password via `$__file{...}` from sops secret
- `homelab/loki/default.nix` — Loki on `127.0.0.1:3100` (tsdb/v13 schema, filesystem storage, 30d retention), Promtail reading journald

## Files Modified
- `homelab/default.nix` — uncommented prometheus/grafana/loki imports
- `homelab/caddy/default.nix` — added `@grafana` and `@prometheus` virtual hosts
- `machines/nixos/pebble/default.nix` — enabled the three services

## Configuration Notes
- All three services bind to `127.0.0.1` only; Caddy exposes Grafana and Prometheus via TLS
- Grafana admin password uses `$__file{/run/secrets/grafana/admin_password}` syntax (Grafana INI native interpolation); if this fails at runtime, fallback is `EnvironmentFile` with `GF_SECURITY_ADMIN_PASSWORD=...`
- Promtail port 3031 (internal), pushes journald to Loki at `localhost:3100`
- Loki `http_listen_address` — verify key name during first build (may surface as Nix eval error)
- No firewall changes needed: ports 80/443 already open via Caddy

## Pre-Deploy Action Required
```bash
just edit-secrets
# Add (plaintext password, single line, no key=value wrapper):
# grafana/admin_password: "YourStrongPasswordHere"
```

## Bugs Fixed During Deployment
1. **Loki compactor**: `compactor.delete_request_store = "filesystem"` required when `retention_enabled = true` — Loki's config validator rejects the build without it.
2. **Promtail 226/NAMESPACE**: NixOS promtail module sets `PrivateMounts=true` + `ReadWritePaths=/var/lib/promtail` but does not declare `StateDirectory`, so the directory is never created. systemd tries to bind-mount the path into the private namespace at startup and fails with `226/NAMESPACE` if it's absent. Fixed with `systemd.tmpfiles.rules = [ "d /var/lib/promtail 0750 promtail promtail -" ]`.

## Verification (All Passed 2026-04-14)
- [x] `systemctl status prometheus grafana loki promtail` — all active
- [x] `https://prometheus.grab-lab.gg` loads; Targets page shows node exporter **UP**
- [x] `https://grafana.grab-lab.gg` loads; login with `admin` + sops password
- [x] Grafana → Connections → Prometheus datasource → Test: green
- [x] Grafana → Connections → Loki datasource → Test: green
- [x] Grafana → Explore → Loki → `{job="systemd-journal"}` returns logs
