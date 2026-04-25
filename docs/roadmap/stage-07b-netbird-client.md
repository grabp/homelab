# Stage 7b: VPN — Homelab Client + Routes + DNS + ACLs

## Status
COMPLETE (2026-04-15)

## Files Created
- `homelab/netbird/default.nix` — NetBird client module with `services.netbird.clients.wt0`

## Files Modified
- `homelab/default.nix` — enabled `./netbird` import
- `machines/nixos/pebble/default.nix` — added `services.resolved` with `DNSStubListener=no`, enabled `my.services.netbird`
- `homelab/pihole/default.nix` — removed `services.resolved.enable = false` (now centralized in pebble/default.nix)
- `machines/nixos/vps/default.nix` — added coturn firewall rules (TCP/UDP 3478+5349, UDP 49152-65535)
- `machines/nixos/vps/netbird-server.nix` — fixed STUN URI scheme + TimeBasedCredentials
- `flake.nix` — added `nixpkgs-unstable` input for netbird package overlay
- `homelab/netbird/default.nix` — added `nixpkgs.overlays` to pull netbird from unstable (0.68.1)

## Configuration Notes (Pebble Client)
- `services.resolved` with `DNSStubListener=no` centralized in pebble/default.nix (Pattern 15)
- `services.netbird.useRoutingFeatures = "both"` enables IP forwarding for route advertisement
- `login.enable` NOT used — `netbird-wt0-login` oneshot gets SIGTERM'd during `nixos-rebuild switch` due to a race between daemon socket readiness and activation lifecycle ("Start request repeated too quickly"). One-time login done manually; credentials persist in `/var/lib/netbird-wt0/` across reboots.
- `config.ManagementURL` does NOT work in netbird 0.60.2 — crashes with "cannot unmarshal string into Go struct field Config.ManagementURL of type url.URL". Set via `--management-url` on first login.
- `sops-install-secrets.service` does NOT exist — sops-nix uses activation scripts, not a systemd unit.
- **netbird package override required** — nixos-25.11 ships 0.60.2 which is protocol-incompatible with ≥0.68.x management servers. WireGuard handshakes never complete; ICE connects then drops with "do not switch to Relay". Fixed via `nixpkgs.overlays` pulling netbird from `nixpkgs-unstable` (0.68.1). Use `lib.mkMerge` to combine the always-on overlay with the `lib.mkIf cfg.enable` conditional config block.

## Bugs Fixed on VPS (machines/nixos/vps/)
- **`services.coturn` does NOT open firewall ports** — comment in default.nix was wrong. Added `networking.firewall.allowedTCPPorts = [80 443 3478 5349]`, `allowedUDPPorts = [3478 5349]`, `allowedUDPPortRanges = [{from=49152; to=65535;}]` explicitly.
- **STUN URI missing scheme** — `"${domain}:3478"` → `"stun:${domain}:3478"` (client rejected with "unknown scheme type")
- **TimeBasedCredentials=false** — management server was issuing static credentials incompatible with coturn's `use-auth-secret`. Changed to `true` so HMAC time-based credentials are used.
- **Stale config.json** — after earlier failed deploys, `/var/lib/netbird-wt0/config.json` had a bad `ManagementURL` string from a previous iteration. Required manual `sudo rm /var/lib/netbird-wt0/config.json && sudo systemctl restart netbird-wt0`.
- **nixpkgs 25.11 netbird 0.60.2 ↔ management 0.68.3 protocol incompatibility** — `Last WireGuard handshake: -` for all peers, `Forwarding rules: 0`. ICE negotiates briefly then "ICE disconnected, do not switch to Relay. Reset priority to: None". Root cause: relay/signaling protocol changed in 0.68.x. Fixed by overlaying netbird 0.68.1 from nixpkgs-unstable.

## One-Time Post-Deploy Login (Already Done)
```bash
sudo netbird-wt0 up \
  --management-url https://netbird.grab-lab.gg \
  --setup-key-file /run/secrets/netbird/setup_key
```

## Verification (All Passed 2026-04-15)
- [x] `netbird-wt0 status -d` — relays `Available`, peers `Connected`, WireGuard handshake established
- [x] `systemctl status systemd-resolved` — running; port 53 held by Pi-hole
- [x] iPhone on cellular: ping `100.102.154.38` (overlay) and `192.168.10.50` (LAN) both work
- [x] `https://grafana.grab-lab.gg` loads from cellular via VPN + route + DNS
- [x] Dashboard → Network Routes: `192.168.10.0/24` active, pebble as routing peer
- [x] Dashboard → DNS: `grab-lab.gg` match-domain → pebble overlay IP (`100.102.154.38`) port 53
- [x] ACL policies hardened — completed 2026-04-19 (All→All deleted, group-scoped policies added)
