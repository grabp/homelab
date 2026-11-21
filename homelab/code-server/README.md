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
| 8484 | 127.0.0.1 | code-server web UI (no own auth) |
| 4181 | 127.0.0.1 | oauth2-proxy (Kanidm OIDC) |

Both bound to loopback — Caddy terminates TLS and proxies `code.<domain>` to
oauth2-proxy, which proxies authenticated requests to code-server. Not opened
in the firewall.

## Authentication

Kanidm OAuth2 client `vscode`, scope map **`homelab_admins` only** (code-server
has write access to the HA config and a shell). code-server itself runs without
a password. The oauth2-proxy session cookie is same-site with `ha.<domain>`, so
the HA "Webpage" dashboard embeds it without a prompt — but the first login must
happen in a normal tab (Kanidm's login page cannot be framed).

## Secrets

| Key | File | Format | Purpose |
|-----|------|--------|---------|
| `kanidm/vscode_client_secret` | `secrets/pebble.yaml` | plain (64 hex) | read by Kanidm provisioning |
| `oauth2-proxy/vscode_env` | `secrets/pebble.yaml` | env file | `OAUTH2_PROXY_CLIENT_SECRET=<same value>`, `OAUTH2_PROXY_COOKIE_SECRET=<32 chars>` |

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
