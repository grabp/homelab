---
service: netbird-server
stage: 7a
machine: vps
status: deployed
---

# NetBird Server

## Purpose

NetBird VPN control plane running on the VPS. Provides peer discovery, relay,
and the management dashboard for all NetBird clients (pebble, boulder, VPS
itself, mobile/laptop peers).

Three OCI containers + one native service:

| Component | Image | Port | Purpose |
|-----------|-------|------|---------|
| management | `netbirdio/management:0.68.3` | `127.0.0.1:8080` | REST/gRPC API, peer registry |
| signal | `netbirdio/signal:0.68.3` | `127.0.0.1:10000` | P2P connection coordination |
| dashboard | `netbirdio/dashboard:v2.36.0` | `127.0.0.1:3000` | React SPA |
| coturn | native | `3478`, `5349`, `49152–65535` | STUN/TURN relay |

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 8080 | TCP | localhost | Management API (proxied by Caddy) |
| 10000 | TCP | localhost | Signal gRPC (proxied by Caddy) |
| 3000 | TCP | localhost | Dashboard (proxied by Caddy) |
| 3478 | TCP+UDP | internet | STUN/TURN |
| 5349 | TCP+UDP | internet | TURN TLS |
| 49152–65535 | UDP | internet | TURN relay range |

## Secrets

| Secret key | Owner | Purpose |
|------------|-------|---------|
| `netbird/turn_password` | `turnserver` | coturn HMAC secret + TURN credentials |
| `netbird/encryption_key` | root | SQLite data-at-rest encryption |
| `pocket-id/netbird-env` | root | `NETBIRD_IDP_MGMT_EXTRA_API_TOKEN` for user sync |

## Depends on

- `pocket-id` module — Pocket ID is the OIDC provider; management validates
  JWTs against `https://pocket-id.grab-lab.gg/.well-known/openid-configuration`.
- `caddy` module — TLS termination and routing for all three container ports.
- `homelab/netbird-client` module — VPS is also a NetBird peer; the unstable overlay
  (in the client module) provides the peer binary.

## DNS

`netbird.grab-lab.gg` → VPS public IP (Caddy serves management + dashboard).

## Known gotchas

- management.json is generated at runtime (systemd oneshot) so secrets are never
  in the Nix store. The template lives in the Nix store with `TURN_PLACEHOLDER`
  and `ENC_PLACEHOLDER` substituted by `jq` at boot.
- coturn needs read access to Caddy's ACME certs (`turnserver` in `caddy` group).
  coturn starts with `Restart=on-failure`; it will retry until Caddy has the cert.
- Container DNS cannot resolve `pocket-id.grab-lab.gg` (no Pi-hole on VPS).
  `--add-host` pins it to the VPS public IP so OIDC discovery works from inside
  the management container.
- `EmbeddedIdP.Enabled = false` — built-in Dex is disabled. `IdpManagerConfig`
  must be absent when using Pocket ID (only needed for Auth0/Zitadel/Keycloak).
- First login after switching from embedded Dex: users are created with
  `blocked=1 / pending_approval=1`. Approve via SQLite before logging in.

## Backup / restore

State: `/var/lib/netbird-mgmt/` — SQLite DB and generated management.json.
Backed up via restic (Stage 10). After restore, re-generate management.json
by restarting `netbird-management-config.service`.
