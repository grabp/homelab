---
service: homepage
stage: 8
machine: pebble
status: deployed
---

# Homepage

## Purpose

Homelab dashboard showing links and status tiles for all services. Accessible
at `home.grab-lab.gg`. Protected by oauth2-proxy in front of Homepage — Caddy
routes to oauth2-proxy which enforces Kanidm OIDC login, then proxies
authenticated requests to Homepage.

Architecture: Caddy → oauth2-proxy (4180) → Homepage (3010).

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 3010 | TCP | localhost | Homepage web UI (remapped from 3000 to avoid Grafana conflict) |
| 4180 | TCP | localhost | oauth2-proxy (Caddy's actual backend for `home.grab-lab.gg`) |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `kanidm/homepage_client_secret` | plaintext secret | OAuth2 client secret (consumed by Kanidm provisioning) |
| `oauth2-proxy/homepage_env` | env file | `OAUTH2_PROXY_CLIENT_SECRET=<secret>` + `OAUTH2_PROXY_COOKIE_SECRET=<secret>` |

## Depends on

- Kanidm (OIDC provider for oauth2-proxy)
- Caddy (TLS termination and routing)

## DNS

`home.grab-lab.gg` → Caddy wildcard vhost → `localhost:4180` (oauth2-proxy).

## OIDC

Provider: Kanidm (`services.kanidm.provision.systems.oauth2."homepage"`).

- Issuer: `https://id.grab-lab.gg/oauth2/openid/homepage`
- Client ID: `homepage`
- Scopes: `openid profile email`
- PKCE: S256 (`OAUTH2_PROXY_CODE_CHALLENGE_METHOD = "S256"`)

oauth2-proxy runs as a Podman OCI container with `--network=host`.

## Known gotchas

- `allowedHosts` must be set to the public hostname — without it Homepage
  returns 403 when accessed through a reverse proxy.
- oauth2-proxy `OAUTH2_PROXY_COOKIE_SECRET` must be 16, 24, or 32 bytes
  (base64-encoded). Generate with: `openssl rand -base64 32`.
- Kanidm's per-client issuer URL (`/oauth2/openid/homepage`) is the correct
  value for `OAUTH2_PROXY_OIDC_ISSUER_URL` — not the global issuer.
- Services without a web UI (e.g. Caddy) should omit `href` in the config —
  Homepage renders them as non-clickable informational tiles.

## Backup / restore

State: `/var/lib/homepage-dashboard/` — user-defined service configs if edited
via the web UI. All config is declarative in the Nix module, so no backup is
strictly required. The oauth2-proxy container is stateless.
