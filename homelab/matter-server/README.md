---
service: matter-server
stage: 9b
machine: pebble
status: deployed
---

# Matter Server

## Purpose

Matter/Thread smart home protocol server. Enables Home Assistant to commission
and control Matter devices (Thread border router, Eve, Nanoleaf, etc.) via the
`ws://127.0.0.1:5580/ws` WebSocket API. Runs as a Podman OCI container.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 5580 | TCP | localhost | WebSocket API (HA connects at `ws://127.0.0.1:5580/ws`) |

Matter also uses IPv6 link-local multicast on the host network interface for
device discovery — no fixed port.

## Secrets

None.

## Depends on

- Avahi (mDNS — Matter devices discovered via mDNS on the local network)

## DNS

Not exposed via Caddy.

## OIDC

Not applicable.

## Known gotchas

- **Host networking is mandatory** — Matter uses IPv6 link-local multicast.
  Bridge networking breaks device discovery entirely.
- **IPv6 forwarding must be disabled:**
  `boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 0`
  If enabled, Matter devices experience up to 30-minute reachability outages.
- **D-Bus access required** for Bluetooth commissioning:
  `/run/dbus:/run/dbus:ro` volume mount + `--security-opt=label=disable`.
- `services.matter-server` native module exists but the CHIP SDK build is
  intractable on NixOS (nixpkgs #255774) — use OCI container.
- `python-matter-server` is in maintenance mode; a `matter.js` rewrite is in
  progress. Current Python v8.x remains stable and API-compatible with HA.
- HA integration: Settings → Devices & Services → Matter → `ws://127.0.0.1:5580/ws`.

## Backup / restore

State: `/var/lib/matter-server/` — Matter fabric data, device commissioning
records. Included in restic via `/var/lib` path. If lost, devices need to be
re-commissioned (factory reset + re-pair via HA).
