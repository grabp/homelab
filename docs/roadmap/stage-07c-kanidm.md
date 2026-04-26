---
kind: roadmap
stage: 7c
title: Identity Provider (Kanidm)
status: complete
---

# Stage 7c: Identity Provider — Kanidm

## Status
COMPLETE (verified 2026-04-16)

## Files Created
- `homelab/kanidm/default.nix` — Kanidm module: self-signed TLS cert oneshot, server binding on `127.0.0.1:8443` + LDAPS on `127.0.0.1:636`, declarative provisioning (grabowskip person + homelab_users/homelab_admins groups + grafana OAuth2 client), sops secrets, firewall port 636

## Files Modified
- `homelab/default.nix` — enabled `./kanidm` import, updated stage comments
- `homelab/caddy/default.nix` — added `@kanidm` virtual host for `id.grab-lab.gg` → `localhost:8443` with `tls_insecure_skip_verify`
- `homelab/grafana/default.nix` — added `"auth.generic_oauth"` OIDC block with `use_pkce = true`, `role_attribute_path` using SPN format; added `kanidm/grafana_client_secret` sops declaration with `restartUnits`
- `machines/nixos/pebble/default.nix` — added `my.services.kanidm.enable = true`

## Configuration Notes
- **Package override required**: nixos-25.11 `services.kanidm` module defaults to `pkgs.kanidm_1_4` (EOL, removed). Must explicitly set `services.kanidm.package = pkgs.kanidmWithSecretProvisioning_1_9`. `_1_7` is also insecure/removed. Use `_1_9` (1.9.x).
- **"admin" username is reserved**: Kanidm has a built-in system account named `admin`. Provisioning a person named `admin` → 409 Conflict. Use a distinct username (`grabowskip`).
- **sops secret ownership**: provisioning `ExecStartPost` runs as the `kanidm` user. Default `root:root 0400` → permission denied. Fix: `sops.secrets."kanidm/admin_password" = { owner = "kanidm"; }` (same for `idm_admin_password`).
- **Self-signed cert must have `CA:FALSE`**: OpenSSL default self-signed certs have `CA:TRUE`. Kanidm 1.9's strict TLS rejects them (`CaUsedAsEndEntity` error). The oneshot script uses `-addext "basicConstraints=CA:FALSE"` + `-addext "subjectAltName=IP:127.0.0.1,DNS:id.<domain>"`. Also detects and regenerates old bad certs.
- **`enableClient = true` requires `clientSettings`**: module enforces this. Use `environment.systemPackages = [ pkgs.kanidmWithSecretProvisioning_1_9 ]` instead to put CLI in PATH without the constraint.
- **PKCE enforced by default**: Kanidm 1.9 requires PKCE on all OAuth2 clients. Grafana must set `use_pkce = true` in `"auth.generic_oauth"`.
- **Groups returned as SPNs**: Kanidm returns groups in the `groups` claim as full SPNs (`groupname@kanidm-domain`, e.g. `homelab_admins@id.grab-lab.gg`). Grafana `role_attribute_path` must match the full SPN: `contains(groups[*], 'homelab_admins@id.grab-lab.gg') && 'Admin' || 'Viewer'`.
- `provision.instanceUrl = "https://127.0.0.1:8443"` + `acceptInvalidCerts = true` — provisioning connects directly (not via Caddy) and accepts the self-signed cert.
- `basicSecretFile` for the Grafana OAuth2 client enables single-phase deploy — secret pre-generated in sops, shared between Kanidm provision and Grafana config.
- `kanidm/grafana_client_secret` with `mode = "0444"` — world-readable so both kanidm provisioning and grafana (`$__file{...}`) can read it.
- Port 636 (LDAPS) opened proactively for future Jellyfin integration; port 8443 NOT exposed externally.
- Pi-hole wildcard `address=/grab-lab.gg/192.168.10.50` already covers `id.grab-lab.gg` — no Pi-hole changes needed.

## Post-Deploy: Set Person Login Password
```bash
# CLI is in PATH after deploy (added via environment.systemPackages)
kanidm --url https://id.grab-lab.gg login --name idm_admin
# (password: sudo cat /run/secrets/kanidm/idm_admin_password)
kanidm --url https://id.grab-lab.gg person credential create-reset-token grabowskip
# use the printed URL to set a password via browser
```

## Verification (All Passed 2026-04-16)
- [x] `systemctl status kanidm kanidm-tls-cert` — both active
- [x] `curl -k https://127.0.0.1:8443/status` — returns JSON
- [x] `curl -sI https://id.grab-lab.gg | head -3` — HTTP 200 with valid TLS
- [x] `kanidm --url https://id.grab-lab.gg system oauth2 list --name admin` — shows `grafana` client
- [x] `https://grafana.grab-lab.gg` — "Sign in with Kanidm" button appears
- [x] Grafana OIDC round-trip completes, `grabowskip` lands with Admin role
