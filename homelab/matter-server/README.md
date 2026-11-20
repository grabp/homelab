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
- **D-Bus mount kept** (`/run/dbus:/run/dbus:ro` + `--security-opt=label=disable`)
  but Bluetooth commissioning through the server is not verified with the
  unprivileged matterjs-server image (D-Bus authenticates by UID). Commission
  new devices via the Home Assistant companion app instead.
- **Runs as UID 1000** — `/var/lib/matter-server` must be owned by `1000:1000`.
- **Device ping** uses the system `ping` as UID 1000: needs
  `net.ipv4.ping_group_range` to include GID 1000 (check with `sysctl net.ipv4.ping_group_range`).
- `services.matter-server` native module exists but the CHIP SDK build is
  intractable on NixOS (nixpkgs #255774) — use OCI container.
- `python-matter-server` was archived in June 2026. Replaced by
  `ghcr.io/matter-js/matterjs-server` (same WebSocket API, same data dir).
- HA integration: Settings → Devices & Services → Matter → `ws://127.0.0.1:5580/ws`.

## Migration from python-matter-server (2026-11)

matterjs-server reads `chip.json` + `<fabric-id>.json` from `/data` and migrates
them into its own storage (`server/`, `ota/`, `certificates/`, `vendors/`) on the
first start. First start: logs "no addresses known" for each node (expected),
then re-discovers and re-interviews every node — Thread devices come online one
by one, so allow several minutes.

Before the first start:
```bash
sudo systemctl stop podman-matter-server
sudo cp -a /var/lib/matter-server /var/lib/matter-server.python-backup
sudo chown -R 1000:1000 /var/lib/matter-server
```

Rollback to python-matter-server: stop the container, restore
`/var/lib/matter-server.python-backup`, switch the image back. matterjs-server
keeps `<fabric-id>.json` updated for added/removed nodes, but never run both
servers on the same data at once.

## Backup / restore

State: `/var/lib/matter-server/` — Matter fabric data, device commissioning
records. Included in restic via `/var/lib` path. If lost, devices need to be
re-commissioned (factory reset + re-pair via HA).
