# Stage 8: Homepage Dashboard

## Status
COMPLETE (implemented 2026-04-16, auth added 2026-04-19)

## Files Created
- `homelab/homepage/default.nix` — Homepage module: `services.homepage-dashboard`, port 3010, services/bookmarks config, oauth2-proxy OCI container (port 4180)

## Files Modified
- `homelab/default.nix` — enabled `./homepage` import
- `homelab/caddy/default.nix` — added `@home` virtual host → oauth2-proxy:4180 (was direct to Homepage:3010)
- `homelab/kanidm/default.nix` — added `homepage` OAuth2 client
- `machines/nixos/pebble/default.nix` — `my.services.homepage.enable = true`

## Configuration Notes
- Native `services.homepage-dashboard` module (homepage-dashboard 1.7.0 in nixos-25.11)
- Port 3010 (remapped from default 3000 to avoid Grafana conflict)
- `allowedHosts = "home.grab-lab.gg"` required for reverse-proxy access
- Services grouped into four sections: Infrastructure (Pi-hole, Caddy), Security (Vaultwarden, Kanidm), Monitoring (Grafana, Prometheus), Networking (NetBird)
- Pi-hole wildcard `address=/grab-lab.gg/192.168.10.50` already covers `home.grab-lab.gg` — no Pi-hole changes needed
- **Auth**: oauth2-proxy (port 4180) in front of Homepage. Kanidm `homepage` OAuth2 client with PKCE. Unauthenticated requests redirected to Kanidm login.
- Caddy → oauth2-proxy:4180 → Homepage:3010. `homelab_users` group members can authenticate.
- Session cookie valid 168h (7 days, oauth2-proxy default).
- Two sops secrets required: `kanidm/homepage_client_secret` and `oauth2-proxy/homepage_env`.

## Bugs Fixed During oauth2-proxy Deployment
1. **Cookie secret size**: `openssl rand -base64 32` outputs 44 chars; oauth2-proxy requires exactly 16, 24, or 32 bytes. Use `openssl rand -hex 16` (32 hex chars = 32 bytes).
2. **OAUTH2_PROXY_UPSTREAM env var ignored**: oauth2-proxy v7.8.1 does not reliably read `OAUTH2_PROXY_UPSTREAM` from the environment (Viper mapping issue). Fixed by passing `--upstream=http://127.0.0.1:3010/` as a CLI argument via `cmd` in the container spec. Trailing slash required.
3. **Kanidm forward_auth not viable**: Pattern 22's `/ui/oauth2/token/check` endpoint does not exist in Kanidm 1.9 (no cookie-based session support). oauth2-proxy with Kanidm as OIDC backend is the correct approach.

## Pre-Deploy Actions Required
```bash
just edit-secrets
# Add:
# kanidm/homepage_client_secret: "$(openssl rand -base64 32)"
# oauth2-proxy/homepage_env: |
#   OAUTH2_PROXY_CLIENT_SECRET=<same as above>
#   OAUTH2_PROXY_COOKIE_SECRET=<openssl rand -hex 16>
```

## Verification (All Passed 2026-04-19)
- [x] `systemctl status homepage-dashboard` — active
- [x] `https://home.grab-lab.gg` loads dashboard with valid TLS
- [x] Four service groups visible: Infrastructure, Security, Monitoring, Networking
- [x] Unauthenticated access redirects to Kanidm login at `https://id.grab-lab.gg`
- [x] After Kanidm login, redirected back to Homepage
- [x] `sudo podman ps | grep oauth2-proxy` — container running
