---
service: pihole
stage: 5
machine: pebble
status: deployed
---

# Pi-hole

## Purpose

LAN DNS sinkhole and split-DNS resolver. Blocks ad/tracking domains and
provides split DNS so `*.grab-lab.gg` resolves to pebble's LAN IP internally
rather than going through Cloudflare. Upstream DNS: Cloudflare (1.1.1.1 / 1.0.0.1).

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 53   | TCP+UDP  | LAN | DNS queries |
| 8089 | TCP | localhost | Web UI (proxied by Caddy → `pihole.grab-lab.gg`) |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `pihole/env` | `FTLCONF_webserver_api_password=<password>` | Web UI admin password |

## Depends on

- Nothing (first service to deploy; others rely on its DNS)

## DNS

Pi-hole is itself the DNS provider. Split-DNS written at activation time to
`/var/lib/pihole-dnsmasq/04-grab-lab.conf`:

```
address=/netbird.grab-lab.gg/<vpsIP>
address=/pocket-id.grab-lab.gg/<vpsIP>
address=/grab-lab.gg/<pebbleIP>   # wildcard
```

`systemd-resolved` must have `DNSStubListener=no` so Pi-hole can bind port 53.

## OIDC

Not applicable.

## Known gotchas

- `services.pihole` does **not** exist in nixpkgs — must use OCI container.
- Pi-hole v6 changed web server from lighttpd to built-in; use
  `FTLCONF_webserver_api_password` (not `WEBPASSWORD`).
- `FTLCONF_misc_etc_dnsmasq_d = "true"` is required for Pi-hole v6 to read
  files in `/etc/dnsmasq.d/`.
- Do **not** use `server=/domain/ip` in conf-dir files — Pi-hole v6 bug #6279
  silently drops it. Use `FTLCONF_dns_revServers` for conditional forwarding.
- Container FTL process runs as UID/GID 1000; `/var/lib/pihole` must be owned
  by `1000:1000` or SQLite WAL writes fail with "readonly database".
- Podman/Netavark DNAT rules for port 53 are flushed when the firewall reloads.
  `podman-pihole` is wired with `partOf = [ "firewall.service" ]` so it
  restarts automatically after a firewall reload.

## Backup / restore

State: `/var/lib/pihole/` — Pi-hole blocklists, FTL database, gravity.db.
Included in restic via `/var/lib` path. On restore, Pi-hole re-runs
`pihole -g` to refresh gravity from configured adlists.
