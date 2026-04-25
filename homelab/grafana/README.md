---
service: grafana
stage: 6
machine: pebble
status: deployed
---

# Grafana

## Purpose

Metrics dashboards and alerting UI. Connects to Prometheus (metrics) and Loki
(logs) as datasources. Access is protected by Kanidm OIDC — `homelab_admins`
group members get Admin role, everyone else gets Viewer.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 3000 | TCP | localhost | Web UI (proxied by Caddy → `grafana.grab-lab.gg`) |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `grafana/admin_password` | plaintext password | Grafana local admin fallback |
| `kanidm/grafana_client_secret` | plaintext secret | OAuth2 client secret for Kanidm OIDC |

Secret ownership: `grafana/admin_password` → owner `grafana`; `kanidm/grafana_client_secret` → owner `kanidm`, group `grafana`, mode `0440` (both services need read access).

## Depends on

- Prometheus (`my.services.prometheus.port` used in datasource provisioning)
- Loki (`my.services.loki.port` used in datasource provisioning)
- Kanidm (OIDC provider for login)

## DNS

`grafana.grab-lab.gg` → Caddy wildcard vhost → `localhost:3000`.

## OIDC

Provider: Kanidm (`services.kanidm.provision.systems.oauth2."grafana"`).

- Issuer: `https://id.grab-lab.gg/oauth2/openid/grafana`
- Client ID: `grafana`
- Scopes: `openid profile email groups`
- Role mapping: `contains(groups[*], 'homelab_admins@id.grab-lab.gg') && 'Admin' || 'Viewer'`
- PKCE: required (`use_pkce = true`)

Server-side token/userinfo calls go to `https://127.0.0.1:8443` with
`tls_skip_verify_insecure = true` (Kanidm self-signed cert).

## Known gotchas

- `settings.server.root_url` must match the public Caddy hostname for OAuth
  redirect URIs to validate correctly.
- Kanidm returns groups as SPNs (`homelab_admins@id.grab-lab.gg`), not bare
  names — `role_attribute_path` must use the full SPN.
- PKCE is enforced by Kanidm 1.9; omitting `use_pkce = true` causes
  "Invalid state / No PKCE code challenge" errors.
- Use `$__file{/run/secrets/...}` syntax for `admin_password` — written
  verbatim into `grafana.ini` and resolved at runtime.

## Backup / restore

State: `/var/lib/grafana/` — SQLite DB with dashboard metadata and alerts.
Datasources and dashboards provisioned declaratively; only manual UI changes
need a backup. Included in restic via `/var/lib` path.
