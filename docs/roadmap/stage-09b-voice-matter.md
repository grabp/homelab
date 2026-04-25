---
kind: roadmap
stage: 9b
title: Voice Pipeline + ESPHome + Matter
status: complete
---

# Stage 9b: Services (Voice Pipeline + ESPHome + Matter Server)

## Status
COMPLETE (implemented 2026-04-18)

## Files Created
- `homelab/wyoming/default.nix` — Wyoming voice pipeline: Faster-Whisper STT (port 10300), Piper TTS (port 10200), OpenWakeWord (port 10400); native NixOS modules
- `homelab/matter-server/default.nix` — Matter Server OCI container: `--network=host`, D-Bus mount, Avahi ordering, IPv6 enabled, IPv6 forwarding disabled

## Files Modified
- `homelab/home-assistant/default.nix` — added ESPHome OCI container (`--network=host`, port 6052) as `my.services.homeAssistant.esphome.*` sub-option; added Avahi mDNS service configuration
- `homelab/default.nix` — added `./wyoming` and `./matter-server` imports
- `homelab/caddy/default.nix` — added `@esphome` virtual host (esphome.grab-lab.gg → port 6052)
- `homelab/homepage/default.nix` — added ESPHome to "Home Automation" service group
- `machines/nixos/pebble/default.nix` — enabled `my.services.wyoming`, `my.services.matterServer`, `my.services.homeAssistant.esphome`

## Configuration Notes
- Wyoming: all three services native NixOS modules; `lib.mkForce "all"` ProcSubset override kept as documentation (nixos-25.11 already ships the fix from PR #372898)
- OpenWakeWord: `preloadModels` was removed in wyoming-openwakeword v2.0.0 — built-in models load automatically; do not set this option in nixos-25.11
- ESPHome: OCI container (`ghcr.io/esphome/esphome:2026.3.1`) — native `services.esphome` has three unresolved bugs (DynamicUser path, missing pyserial, missing font component)
- Matter Server: OCI container (`ghcr.io/home-assistant-libs/python-matter-server:stable`) — CHIP SDK not buildable natively; `--security-opt=label=disable` required for Bluetooth/D-Bus; `boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkDefault 0` prevents 30-minute reachability outages
- Avahi (`services.avahi.openFirewall = true`) added to home-assistant module — used by ESPHome and Matter Server for mDNS device discovery
- ESPHome and Matter Server: `systemd.services.podman-*.wants/after = ["avahi-daemon.service"]` (Pattern 16C)
- ESPHome options co-located as sub-options of `my.services.homeAssistant.esphome.*` per STRUCTURE.md
- lib.mkMerge pattern used in home-assistant/default.nix (same as netbird module, Pattern 14)

## Post-Deploy Steps (Manual, In Order)
1. `systemctl status wyoming-faster-whisper-main wyoming-piper-main wyoming-openwakeword` — verify all three active
2. `sudo podman ps` — verify `esphome` and `matter-server` containers running
3. HA → Settings → Voice assistants → create pipeline: Whisper (localhost:10300), Piper (localhost:10200), OpenWakeWord (localhost:10400)
4. HA → Settings → Devices & Services → ESPHome → Add Integration → host `127.0.0.1`, port `6052`
5. HA → Settings → Devices & Services → Matter → Add Integration → `ws://127.0.0.1:5580/ws`
6. `https://esphome.grab-lab.gg` loads ESPHome dashboard with valid TLS

## Verification (Verified 2026-04-18)
- [x] `systemctl status wyoming-faster-whisper-main wyoming-piper-main wyoming-openwakeword` — all active
- [x] `sudo podman ps` — shows `esphome` and `matter-server` containers running
- [x] HA voice assistant: hold mic button in mobile app, speak a command — HA responds with TTS
- [x] `https://esphome.grab-lab.gg` loads ESPHome dashboard; ESP devices discovered
- [x] Matter integration configured at `ws://127.0.0.1:5580/ws`
