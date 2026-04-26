---
service: vaultwarden
stage: 7
machine: pebble
status: deployed
---

# Vaultwarden

## Purpose

Self-hosted Bitwarden-compatible password manager. Stores encrypted vaults for
all household members. Accessible via browser extension, mobile apps, and web
UI at `vault.grab-lab.gg`. Signups disabled after initial account creation.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 8222 | TCP | localhost | Web UI + API (proxied by Caddy → `vault.grab-lab.gg`) |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `vaultwarden/admin_token` | `ADMIN_TOKEN=<token>` | Admin panel at `/admin`; generate with `openssl rand -base64 48` |

Owner: `vaultwarden` user.

## Depends on

- Caddy (TLS termination)

## DNS

`vault.grab-lab.gg` → Caddy wildcard vhost → `localhost:8222`.

## OIDC

Not currently enabled. Native OIDC is available — enable with:

```nix
services.vaultwarden.config = {
  SSO_ENABLED = true;
  SSO_AUTHORITY = "https://id.grab-lab.gg/oauth2/openid/vaultwarden/.well-known/openid-configuration";
};
```

Note: SSO only gates web vault access. The master password is still required
for vault decryption (Bitwarden design — SSO does not replace encryption key).

## Known gotchas

- `SIGNUPS_ALLOWED = false` — set after creating initial accounts. New users
  must be invited via the admin panel.
- `DOMAIN` must be set to the full public URL including `https://` for mobile
  app and browser extension registration.
- `backupDir` creates automatic daily SQLite copies — path is
  `/var/backup/vaultwarden` (outside `/var/lib` to allow separate backup policy).
- Admin token must **not** be stored in plain text — always use sops.

## Backup / restore

**Critical service** — credential loss has severe impact.

- `/var/backup/vaultwarden/` — daily SQLite backups created by `backupDir` option
- `/var/lib/vaultwarden/` — live database

Both paths included in restic. Test restore periodically. Store emergency
recovery sheet offline (paper or encrypted USB).
