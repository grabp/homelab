---
service: code-server
stage: extra
machine: pebble
status: active
---

# code-server

## Purpose

VS Code in the browser. Used for editing Home Assistant configuration files
directly from a browser tab. Runs as a Podman OCI container on pebble with
a configurable workspace path that defaults to `/var/lib/homeassistant`.

Proxied by Caddy on pebble. Accessible at `https://code.grab-lab.gg`.

## Ports

| Port | Interface | Service |
|------|-----------|---------|
| 8484 | 127.0.0.1 | code-server web UI |

Bound to loopback only — Caddy terminates TLS and proxies inbound HTTPS.
Not opened in the firewall.

## Secrets

| Key | File | Format | Purpose |
|-----|------|--------|---------|
| `code-server/env` | `secrets/pebble.yaml` | env file (`PASSWORD=<pw>`) | Web UI login password |

Add via `just edit-secrets-pebble`:
```yaml
code-server/env: |
  PASSWORD=your-password-here
```

## Depends on

- **Caddy** — TLS termination and reverse proxy (Stage 4)
- **Home Assistant** (optional) — default workspace is `/var/lib/homeassistant`

## Storage

| Path | Contents |
|------|----------|
| `/var/lib/code-server` | Extensions, user settings, VS Code config |
| `workspacePath` (default `/var/lib/homeassistant`) | Workspace files (bind-mounted read/write) |

`/var/lib/code-server` is covered by pebble's restic backup (default path `/var/lib`).

## Known Gotchas

**PUID/PGID must match workspace ownership**: The default PUID=0/PGID=0 (root)
matches Home Assistant config files which are created by the HA container running
as root. If pointing the workspace at a directory owned by a non-root user, set
`puid` and `pgid` to the matching UID/GID in the module options.

**Path transparency**: The workspace is mounted at the same absolute path inside
and outside the container (`workspacePath:workspacePath`). This means the terminal
inside code-server sees the same paths as the host, which is useful for running
`systemctl`, checking log paths, etc.

**Pattern 19 (Netavark firewall ordering)**: `podman-code-server` declares
`partOf = [ "firewall.service" ]` so its loopback DNAT mapping is re-registered
after any NixOS firewall reload.

## Backup / Restore

- `/var/lib/code-server` — extensions and user settings; covered by pebble restic.
- The workspace (`workspacePath`) is backed up by its own service's backup procedure
  (e.g. HA config is part of the Home Assistant restic snapshot).
