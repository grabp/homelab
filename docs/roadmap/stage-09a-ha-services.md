# Stage 9a: Services (Mosquitto + HACS + Home Assistant + Uptime Kuma)

## Status
COMPLETE (verified 2026-04-18)

## Files Created
- `homelab/mosquitto/default.nix` — Mosquitto module: `services.mosquitto`, port 1883, `homeassistant` user with readwrite ACL
- `homelab/home-assistant/default.nix` — HA module: Podman OCI container, `--network=host`, `--privileged`, HACS oneshot (Pattern 11 Approach A), activation script for initial `configuration.yaml`
- `homelab/uptime-kuma/default.nix` — Uptime Kuma module: `services.uptime-kuma`, port 3001 on 127.0.0.1

## Files Modified
- `homelab/default.nix` — enabled `./mosquitto`, `./home-assistant`, `./uptime-kuma` imports
- `homelab/caddy/default.nix` — added `@ha` (ha.grab-lab.gg → 8123) and `@uptime` (uptime.grab-lab.gg → 3001) virtual hosts
- `homelab/homepage/default.nix` — added Uptime Kuma to Monitoring group; new "Home Automation" group with Home Assistant
- `machines/nixos/pebble/default.nix` — enabled mosquitto, homeAssistant, uptimeKuma services

## Configuration Notes
- Mosquitto: native `services.mosquitto`; per-listener password auth (NixOS module enforces `per_listener_settings = true`). Pre-hashed passwords inline in config — generate with `mosquitto_passwd`, replace `REPLACE_ME` placeholder before first deploy.
- Home Assistant: `ghcr.io/home-assistant/home-assistant:stable` OCI image. Volumes: `/var/lib/homeassistant:/config`, `/etc/localtime`. Activation script writes minimal `configuration.yaml` (with Caddy trusted proxy config) only on first deploy — does not overwrite on subsequent rebuilds.
- HACS: `systemd.services.hacs-install` oneshot runs before `podman-homeassistant.service`. Downloads latest HACS zip from GitHub, idempotent. Requires completing GitHub OAuth device flow in HA UI after first boot.
- Uptime Kuma: native `services.uptime-kuma`, binds to 127.0.0.1:3001, proxied via Caddy. No sops secrets needed; internal auth handles login.
- HA → Mosquitto soft ordering: `wants/after = ["mosquitto.service"]` on `podman-homeassistant.service` — HA works without MQTT but prefers it to be up first.

## Pre-Deploy Action Required
```bash
# Generate Mosquitto password hash for the homeassistant user:
nix shell nixpkgs#mosquitto --command mosquitto_passwd -c /tmp/p homeassistant
# Paste the hash (everything after "homeassistant:") into homelab/mosquitto/default.nix
# replacing the REPLACE_ME placeholder
```

## Post-Deploy Steps (Manual, In Order)
1. `https://ha.grab-lab.gg` — complete Home Assistant onboarding wizard
2. Settings → Devices & Services → Add Integration → HACS → complete GitHub OAuth device flow
3. Settings → Devices & Services → Add Integration → MQTT → server `127.0.0.1`, port `1883`, user `homeassistant`, password set via mosquitto_passwd
4. Settings → Devices & Services → Add Integration → UniFi Network → requires **local admin** account on controller (not SSO/cloud account)
5. `https://uptime.grab-lab.gg` — create Uptime Kuma admin account on first visit

## Configuration Gotchas (Discovered During Deploy)
- Caddy must use `127.0.0.1:8123` not `localhost:8123` — on dual-stack systems `localhost` resolves to `::1`, which HA rejects as an untrusted proxy even when `::1` is listed in `trusted_proxies`
- After restoring a backup, `configuration.yaml` loses the `http:` block — activation script now detects and re-injects it if `^http:` is absent
- `sudo podman ps` required — Podman runs rootful, container not visible without sudo

## Verification (All Passed 2026-04-18)
- [x] `systemctl status mosquitto` — active
- [x] `sudo podman ps` — shows `homeassistant` container running
- [x] `sudo test -f /var/lib/homeassistant/custom_components/hacs/__init__.py` — HACS present
- [x] `https://ha.grab-lab.gg` loads Home Assistant
- [x] `https://uptime.grab-lab.gg` loads Uptime Kuma
- [x] HA MQTT integration connects to `127.0.0.1:1883`
