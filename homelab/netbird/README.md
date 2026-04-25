---
service: netbird
stage: 6b
machine: pebble
status: deployed
---

# NetBird (client)

## Purpose

WireGuard-based VPN client connecting pebble to the self-hosted NetBird control
plane on the VPS. Advertises the `192.168.10.0/24` LAN route to NetBird peers,
enabling remote access to all homelab services over the mesh without port
forwarding (CGNAT).

This module covers the **pebble client only**. The NetBird server (management,
signal, dashboard, Pocket ID) lives in `machines/nixos/vps/netbird-containers.nix`.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 51820 | UDP | internet | WireGuard tunnel to VPS STUN/TURN relay |

## Secrets

| Secret key | Format | Purpose |
|------------|--------|---------|
| `netbird/setup_key` | plaintext key | One-time registration key from NetBird Dashboard |

## Depends on

- `services.resolved` with `DNSStubListener=no` — frees port 53 for Pi-hole
  while keeping resolved as a routing daemon for NetBird's `resolvectl` calls.

## DNS

`netbird.grab-lab.gg` resolves to the VPS IP (specific Pi-hole entry in
`04-grab-lab.conf` — overrides the wildcard).

After deploy, configure in NetBird Dashboard:
1. DNS → Nameservers → Add: Pi-hole overlay IP, match domain `grab-lab.gg`
2. Network Routes → Add: `192.168.10.0/24`, routing peer = pebble, masquerade enabled

## OIDC

Not applicable to the client. The NetBird server uses Pocket ID (passkey-only
OIDC) for user authentication to the dashboard.

## Known gotchas

- `DNSStubListener=no` in resolved is **required** for Pi-hole + NetBird
  coexistence (Pattern 15 in NIX-PATTERNS.md). Pi-hole holds port 53; resolved
  runs as a routing daemon only.
- Package comes from `nixpkgs-unstable` overlay (production version may differ
  from stable channel).
- `useRoutingFeatures = "both"` enables kernel IP forwarding — prerequisite for
  the `192.168.10.0/24` route advertisement.
- CGNAT connections use relay (ICE candidate: relay) — expect ~7 Mbps / ~85ms.
  This is normal, not a failure.
- **Stale relay bug (GitHub #3936):** shows "Connected" but traffic stops.
  Fix: `netbird-wt0 down && netbird-wt0 up`.
- Route advertisement is configured in the NetBird Dashboard, not in NixOS.

## Backup / restore

State: `/var/lib/netbird/` — WireGuard keys and peer configuration.
If lost, re-register with a new setup key from the NetBird Dashboard.
