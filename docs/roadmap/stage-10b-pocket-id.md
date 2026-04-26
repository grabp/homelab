---
kind: roadmap
stage: 10b
title: Pocket ID — NetBird Passkey IdP
status: complete
---

# Stage 10b: Pocket ID — NetBird Passkey IdP

## Status
COMPLETE (2026-04-20)

Replaced embedded Dex (built into `netbirdio/management`) with Pocket ID, a passkey-only OIDC provider co-located on the VPS. Eliminates password-based NetBird login; all authentication via FIDO2/WebAuthn passkeys.

## Files Created
- `machines/nixos/vps/pocket-id.nix` — Pocket ID OCI container module (port 1411, `/var/lib/pocket-id`)

## Files Modified
- `machines/nixos/vps/default.nix` — added `./pocket-id.nix` import + `my.services.pocketId.enable = true`
- `machines/nixos/vps/caddy.nix` — added `pocket-id.grab-lab.gg` vhost; removed `/oauth2/*` route (embedded Dex gone)
- `machines/nixos/vps/netbird-server.nix` — `EmbeddedIdP.Enabled = false`; `HttpConfig.OIDCConfigEndpoint` + `AuthAudience` pointing at Pocket ID; management container gets `NETBIRD_MGMT_IDP=pocketid` + `NETBIRD_IDP_MGMT_EXTRA_*` env vars; dashboard `AUTH_AUTHORITY/CLIENT_ID/AUDIENCE` updated; `pocket-id/netbird-env` sops secret added
- `homelab/pihole/default.nix` — added `address=/pocket-id.grab-lab.gg/${vars.vpsIP}` DNS override; added `podman exec pihole restartdns reload` to activation script (auto-reload on config change)

## Configuration Notes
- Image: `ghcr.io/pocket-id/pocket-id:v1.3.1@sha256:879760...` (pinned digest)
- Port 1411 bound to `127.0.0.1` only — proxied by Caddy, not exposed directly
- `ALLOW_USER_SIGNUPS = "disabled"` — signups locked after initial admin created
- Cloudflare DNS: A record `pocket-id.grab-lab.gg → 204.168.181.110`
- Pi-hole override so LAN devices bypass the wildcard `*.grab-lab.gg → pebble` for this subdomain
- **Setup page**: `/login/setup` (not `/setup`) in v1.3.1
- OIDC Client ID: `4c1b8f6b-736c-4f52-800b-022c45a8970f` (NetBird client in Pocket ID)
- Sops secret `pocket-id/netbird-env` in `secrets/vps.yaml`: `NETBIRD_IDP_MGMT_EXTRA_API_TOKEN=<token>`
- Sops secret `pocket-id/env` in `secrets/vps.yaml`: `ENCRYPTION_KEY=<base64>`
- Existing NetBird peers stay connected; re-auth triggered on next session expiry

## Bugs Fixed During Deployment
1. **Setup page is `/login/setup`, not `/setup`** (v1.3.1) — `/setup` doesn't exist; navigating there produces a 404 that falls through to the login redirect. Use `/login/setup` directly.
2. **Confidential client → 400 on token exchange** — NetBird dashboard is a browser SPA and never sends a `client_secret`. Creating the Pocket ID OIDC client as "confidential" caused Pocket ID to reject the token request with HTTP 400 "client id or secret not provided". Fix: set **Public client: ON** in the Pocket ID OIDC client settings.
3. **`offline_access` scope unsupported** — Pocket ID v1.3.1 does not advertise `offline_access` in `scopes_supported`. Removed from `AUTH_SUPPORTED_SCOPES` in the dashboard container env.
4. **First login blocked — pending_approval** — After switching IdPs, the Pocket ID IDP manager syncs users from Pocket ID's API and pre-creates them in the NetBird store with `blocked=1` / `pending_approval=1`. The new user can complete OIDC auth but the management API returns "user is pending approval". No self-service escape. Fix: direct SQLite update before first login:
   ```bash
   sudo sqlite3 /var/lib/netbird-mgmt/store.db \
     "UPDATE users SET blocked=0, pending_approval=0, role='owner' \
      WHERE id='<pocket-id-user-uuid>';"
   ```
   No container restart needed — management reads SQLite live.

## Verification (All Passed 2026-04-20)
- [x] `podman ps` shows `pocket-id` container running
- [x] `https://pocket-id.grab-lab.gg` loads login page
- [x] `https://netbird.grab-lab.gg` redirects to Pocket ID for login
- [x] Passkey auth completes → lands on NetBird dashboard
