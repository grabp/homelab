---
service: kanidm
stage: 7c
machine: pebble
status: deployed
---

# Kanidm

## Purpose

Primary identity provider (IdP) for homelab services. Provides OIDC and LDAP
authentication. Accessible only over the NetBird VPN mesh — never exposed
to the internet. All OAuth2 clients are provisioned declaratively in this module
(no web UI clicking required).

Current OAuth2 clients: `grafana`, `homepage`.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 8443 | TCP | localhost | HTTPS (OIDC, admin API — proxied by Caddy with `tls_insecure_skip_verify`) |
| 636  | TCP | LAN | LDAPS (for services needing LDAP, e.g. Jellyfin) |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `kanidm/admin_password` | plaintext password | System admin account |
| `kanidm/idm_admin_password` | plaintext password | IDM admin account (user provisioning) |
| `kanidm/grafana_client_secret` | plaintext secret | OAuth2 client secret for Grafana |
| `kanidm/homepage_client_secret` | plaintext secret | OAuth2 client secret for Homepage |

Secret ownership: admin passwords → owner `kanidm`; client secrets → owner `kanidm`, additional group access as needed.

## Depends on

- Nothing (foundational service; others depend on Kanidm)

## DNS

`id.grab-lab.gg` → Caddy wildcard vhost → `localhost:8443` (with `tls_insecure_skip_verify`).

## OIDC

Kanidm **is** the OIDC provider. Per-client issuer URL pattern:

```
https://id.grab-lab.gg/oauth2/openid/<client-name>/.well-known/openid-configuration
```

Groups are returned as SPNs: `groupname@id.grab-lab.gg`.

To add a new OAuth2 client: add a `systems.oauth2."<name>"` block in
`services.kanidm.provision` and use the `/kanidm-oauth2-client` skill.

## Known gotchas

- Package must be `pkgs.kanidmWithSecretProvisioning_1_9` — `pkgs.kanidm` and
  `pkgs.kanidm_1_4` are EOL/removed in nixos-25.11.
- `"admin"` is a reserved Kanidm system account — do not provision a person
  with that username (409 Conflict).
- Self-signed cert must have `basicConstraints=CA:FALSE` — Kanidm 1.9 rejects
  certs with `CA:TRUE` (`CaUsedAsEndEntity` error). The `kanidm-tls-cert`
  oneshot service regenerates it if needed.
- PKCE is enforced by default on all clients — consumers must set `use_pkce = true`.
- `enableClient = true` requires `clientSettings` — use
  `environment.systemPackages` to add the CLI instead.
- Provisioning `ExecStartPost` runs as the `kanidm` user — sops secrets for
  passwords need `owner = "kanidm"`.

## Backup / restore

State: `/var/lib/kanidm/` — embedded SQLite database + TLS key/cert.
Included in restic via `/var/lib` path. The TLS cert is regenerated automatically
if missing; the database contains all provisioned users and clients.
