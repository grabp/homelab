---
service: caddy
stage: 5
machine: pebble
status: deployed
---

# Caddy

## Purpose

Reverse proxy and TLS termination for all homelab services. Obtains a wildcard
certificate for `*.grab-lab.gg` via Cloudflare DNS-01 ACME challenge. A single
`*.grab-lab.gg` virtual host block dispatches to services by `host` matcher.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 80   | TCP | LAN | ACME HTTP-01 (redirect to 443) |
| 443  | TCP | LAN | HTTPS — all service vhosts |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `caddy/env` | `CLOUDFLARE_API_TOKEN=<token>` | DNS-01 challenge; scoped to Zone:Zone:Read + Zone:DNS:Edit on `grab-lab.gg` |

Owner: `caddy` user (set via `sops.secrets."caddy/env".owner`).

## Depends on

- Pi-hole (split DNS must resolve `*.grab-lab.gg` → pebble LAN IP before services are reachable)
- Kanidm (for oauth2-proxy OIDC auth on Homepage)

## DNS

Pi-hole wildcard entry: `address=/grab-lab.gg/<pebble-LAN-IP>` in
`/var/lib/pihole-dnsmasq/04-grab-lab.conf`. Caddy then routes by `Host:` header.

## OIDC

Not applicable — Caddy is the TLS terminator, not an OIDC client.

## Known gotchas

- Standard `pkgs.caddy` lacks DNS plugins — always use `pkgs.caddy.withPlugins`
  with the `caddy-dns/cloudflare` plugin for DNS-01.
- Plugin version uses pseudo-version format: `@v0.0.0-{date}-{shortrev}`. Set
  `hash = ""` on first build; Nix prints the correct hash in the error.
- Add `resolvers 1.1.1.1` inside the `tls {}` block so ACME TXT lookups bypass
  Pi-hole (which may not yet resolve on first boot).
- Caddy runs as the `caddy` user — sops secret must set `owner = "caddy"`.
- Kanidm backend uses `tls_insecure_skip_verify` because Kanidm uses a
  self-signed cert internally; Caddy provides public TLS to clients.

## Backup / restore

State: `/var/lib/caddy/` — contains ACME certificates. Included in restic via
`/var/lib` path. If lost, Caddy re-issues automatically on next start (rate
limits apply — max 5 duplicate certs per week per Let's Encrypt).
