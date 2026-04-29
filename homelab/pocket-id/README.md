---
service: pocket-id
stage: 10b
machine: vps
status: deployed
---

# Pocket ID

## Purpose

Passkey-only OIDC identity provider. Replaces the embedded Dex IdP that ships
with NetBird management. Runs on the VPS so authentication availability is
independent of pebble. Users log in with WebAuthn/FIDO2 passkeys — no passwords.

Acts as the OIDC provider for the NetBird dashboard (public PKCE client).

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 1411 | TCP | localhost | Pocket ID HTTP API (proxied by Caddy → `pocket-id.grab-lab.gg`) |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `pocket-id/env` | `ENCRYPTION_KEY=<base64>` | AES key for encrypting stored OIDC client secrets |

Generate: `openssl rand -base64 32`. Add via `just edit-secrets-vps`.

## Depends on

- Caddy (VPS) — TLS termination and reverse proxy at `pocket-id.grab-lab.gg`
- NetBird server — references Pocket ID as the external IdP (embedded Dex disabled
  in `netbird-server.nix`)

## DNS

`pocket-id.grab-lab.gg` → VPS public IP → Caddy → `localhost:1411`.

## OIDC

Pocket ID **is** the OIDC provider. It issues tokens consumed by NetBird.

NetBird client configuration (set once in NetBird `management.json`):
- Provider: Pocket ID
- Client ID: noted during post-deploy setup
- Client type: **public** (PKCE, no client secret) — the NetBird dashboard is a
  SPA and cannot keep a secret

Post-deploy setup steps (one-time, already completed 2026-04-20):
1. Browse to `https://pocket-id.grab-lab.gg/setup` — create admin account with passkey
2. Admin → OIDC Clients → Add client (NetBird, public, PKCE on, redirect URIs for `/nb-auth` and `/nb-silent-auth`)
3. Admin → API Keys → create token for NetBird management
4. Admin → Users → create user accounts; assign to NetBird OIDC client

## Known gotchas

- NetBird client must be **public** (`Public client: ON`). A confidential client
  causes `400 client id or secret not provided` from the NetBird dashboard SPA.
- After switching from embedded Dex, the IDP manager imports Pocket ID users with
  `blocked=1, pending_approval=1`. Approve via SQLite before first login:
  ```bash
  sudo sqlite3 /var/lib/netbird-mgmt/store.db \
    "UPDATE users SET blocked=0, pending_approval=0, role='owner'
     WHERE id='<pocket-id-user-uuid>';"
  ```
- `VERSION_CHECK_DISABLED = "true"` and `ANALYTICS_DISABLED = "true"` prevent
  outbound calls to the Pocket ID hosted service.
- `TRUST_PROXY = "true"` is required — Caddy terminates TLS and forwards via HTTP.

## Backup / restore

State: `/var/lib/pocket-id/` — SQLite database (users, OIDC clients, passkey
credentials). Loss requires re-running the full post-deploy setup and
re-registering passkeys. Included in restic via `/var/lib` path.
