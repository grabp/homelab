---
service: home-assistant
stage: 9a
machine: pebble
status: deployed
---

# Home Assistant

## Purpose

Home automation hub. Controls smart lights, sensors, HVAC, and IoT devices.
Integrates with Mosquitto (MQTT), Wyoming voice pipeline (Whisper/Piper/OpenWakeWord),
Matter Server, and ESPHome. HACS installed automatically via oneshot service.

Co-located in this module: **ESPHome** dashboard (optional, `cfg.esphome.enable`).

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 8123 | TCP | LAN | Web UI + API (proxied by Caddy → `ha.grab-lab.gg`) |
| 21064+ | TCP | LAN | HomeKit bridge(s) — one port per bridge instance |
| 6052 | TCP | localhost | ESPHome dashboard (if enabled, proxied via Caddy → `esphome.grab-lab.gg`) |

## Secrets

HA manages its own secrets via `/var/lib/homeassistant/secrets.yaml` — not via sops.

## Depends on

- Mosquitto (MQTT broker — HA waits for it via `wants`/`after`)
- Avahi (mDNS for device discovery)

## DNS

- `ha.grab-lab.gg` → Caddy wildcard vhost → `127.0.0.1:8123`
  (explicit IPv4 — HA rejects `::1` as untrusted proxy in X-Forwarded-For handling)
- `esphome.grab-lab.gg` → Caddy → `localhost:6052`

## OIDC

Not natively supported. Authentication proxied at the Caddy layer via
`forward_auth` (NIX-PATTERNS.md Pattern 22). Internal HA users still exist
for local/LAN access without VPN.

Requires in `configuration.yaml`:
```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - ::1
```
The `ha-init-config` activation script writes this automatically.

## Known gotchas

- OCI container is recommended (not `services.home-assistant`) — upstream
  considers NixOS unsupported; native module freezes HA at branch-off.
- `--network=host` is required for mDNS device discovery (Zigbee, Chromecast,
  Matter multicast, HomeKit).
- HomeKit bridge: each bridge instance needs its TCP port open in the firewall
  (21064 for first, 21065 for second). Configure via `homekitPorts` option.
- `--device=/dev/ttyUSB0` is included for Zigbee/Z-Wave USB adapters.
- UniFi integration requires a **local admin user** on the UniFi controller,
  not an SSO account.
- HACS install: oneshot service downloads from GitHub on first boot. Internet
  access is required on initial deploy.

## Backup / restore

State: `/var/lib/homeassistant/` — HA configuration, automations, custom
components (HACS). Included in restic via `/var/lib` path. ESPHome device
configs: `/var/lib/esphome/`.

On restore, HA re-downloads HACS integrations from the internet on first start.
