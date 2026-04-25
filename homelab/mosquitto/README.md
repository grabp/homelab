---
service: mosquitto
stage: 9a
machine: pebble
status: deployed
---

# Mosquitto

## Purpose

MQTT broker for IoT device communication. Home Assistant connects as a client
to receive sensor readings and send device commands. IoT devices (ESP32,
Zigbee gateway, etc.) publish telemetry to topic namespaces defined in per-user ACLs.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 1883 | TCP | LAN | MQTT (cleartext — LAN-only, not internet-facing) |

## Secrets

No sops secrets — password hashes are stored inline in the Nix config (pre-hashed).
Generate with:
```bash
nix shell nixpkgs#mosquitto --command mosquitto_passwd -c /tmp/passwd <username>
```
Copy the resulting hash into the `hashedPassword` field.

## Depends on

- Nothing (HA depends on Mosquitto, not the reverse)

## DNS

Not exposed via Caddy — MQTT clients connect directly on port 1883.

## OIDC

Not applicable.

## Known gotchas

- The NixOS module sets `per_listener_settings = true` globally — users and
  ACLs must be defined **per listener**, not at the global level.
- Container alternative (`eclipse-mosquitto`) is no longer recommended — native
  NixOS module is fully supported and production-ready.
- `address = "0.0.0.0"` on the listener — firewall restricts access to LAN.
  Do not expose port 1883 to the internet (no TLS on this port).
- `homeassistant` user has `readwrite #` ACL (all topics). Restrict IoT device
  users to specific topic paths.

## Backup / restore

State: `/var/lib/mosquitto/` — in-flight message persistence (if configured).
Mosquitto default is no persistence — no critical data at rest. The Nix config
is the source of truth for users and ACLs.
