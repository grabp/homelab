---
kind: architecture
title: System Overview
tags: [topology, networking, machines]
---

# Overview

This document describes the high-level topology, machine roles, and network architecture of the homelab.

## Machines

| Machine | Role | Hardware | Network | Host |
|---------|------|----------|---------|------|
| **pebble** | Homelab server, primary service host, NetBird routing peer | HP ProDesk 600 G1 | 192.168.10.50/24 (LAN), CGNAT | NixOS 25.11, ZFS |
| **vps** | NetBird control plane, Pocket ID IdP, public entry point | Hetzner CX22 | `<VPS_IP>` (public, from vars.nix) | NixOS 25.11, ext4 |
| **boulder** | Future media server, document management | HP EliteDesk (planned) | 192.168.10.51/24 (LAN) | NixOS 25.11, ZFS |

## Network Topology

```
Internet → (blocked to homelab — no port forwards, CGNAT)

LAN clients → Pi-hole (DNS :53) → resolves *.grab-lab.gg → 192.168.10.50
                                 → Caddy (:443) → localhost:<service-port>

Mobile clients (phone/laptop)
  → UDP 51820 → VPS WireGuard hub (10.10.0.1, public IP from vars.vpsIP)
      ↕ WireGuard (end-to-end encrypted)
  ← pebble (10.10.0.2, behind CGNAT, outbound-only to VPS)
  → DNS: 192.168.10.50 (Pi-hole via tunnel) → *.grab-lab.gg → Caddy → service

pebble ← ISP CGNAT (symmetric NAT, no inbound)
  pebble initiates outbound WireGuard to VPS (10.10.0.1); PersistentKeepalive=25s
  keeps CGNAT mapping alive. VPS routes mobile → pebble → LAN services.
```

### CGNAT — hub-and-spoke eliminates TURN relay

pebble is behind symmetric NAT. Rather than attempting STUN hole-punching (which fails ~100% of the time on symmetric NAT) or maintaining a TURN relay, all mobile traffic routes through the VPS hub. pebble connects outbound to VPS once; the VPS routes packets between mobile clients and pebble without any additional relay infrastructure.

## Wildcard DNS / Caddy Entry-Point Pattern

All services follow the same pattern:

1. **Service binds to localhost** on a unique port
2. **Pi-hole** resolves `*.grab-lab.gg` to pebble's LAN IP
3. **Caddy** listens on `:443` with a wildcard certificate
4. **Caddy routes by subdomain** to the appropriate localhost port

This eliminates:
- Bridge networks and container IP management
- Port forwarding through CGNAT
- Certificate management per-service

## DNS Resolution Flow

```
LAN client queries pihole.grab-lab.gg
    ↓
Pi-hole (dnsmasq) → address=/grab-lab.gg/192.168.10.50
    ↓
Caddy on 192.168.10.50:443 receives request with Host: pihole.grab-lab.gg
    ↓
Caddy @pihole host matcher → reverse_proxy localhost:8089
```

WireGuard clients configure `DNS = 192.168.10.50` in their client config. All DNS queries go to Pi-hole via the tunnel while connected; Pi-hole forwards public domains upstream.

## VPS as WireGuard Hub

The VPS is the only externally reachable endpoint. It runs:

| Service | Purpose |
|---------|---------|
| WireGuard (UDP 51820) | Hub routing all peer traffic |
| Alloy | Log shipping to pebble Loki |

The VPS never sees decrypted application traffic — WireGuard provides end-to-end encryption between peers.

## Service Isolation Strategy

| Isolation Type | Services | Rationale |
|----------------|----------|-----------|
| **Native NixOS modules** | Caddy, Grafana, Prometheus, Loki, Kanidm, Vaultwarden, Mosquitto, Wyoming | First-class integration, systemd sandboxing, seamless secrets |
| **Podman OCI containers** | Pi-hole, Home Assistant, ESPHome, Matter Server | No NixOS module exists, or upstream unsupported |

All services bind to `127.0.0.1` (or `0.0.0.0` for LAN-facing services like Mosquitto). Caddy is the single entry point for all HTTPS traffic.

## ZFS on pebble/boulder

Both homelab machines use ZFS with ephemeral root:

```
zroot
├── root          # Ephemeral (optional rollback)
├── nix           # Nix store — never backed up
├── var           # All service state — backed up
├── home          # User data
├── reserved      # 10G reservation to prevent pool full
└── containers    # ext4 zvol for Podman (acltype compat)
```

**Why ZFS on single disk:**
- Checksumming catches bit rot and silent corruption
- LZ4 compression saves space and improves SSD I/O
- Instant snapshots enable atomic backups

## Key Files

| File | Purpose |
|------|---------|
| `machines/nixos/pebble/default.nix` | pebble host configuration |
| `machines/nixos/vps/default.nix` | VPS host configuration |
| `machines/nixos/vars.nix` | Shared variables (domain, IPs, email) |
| `homelab/caddy/default.nix` | Reverse proxy routing rules |
| `homelab/pihole/default.nix` | DNS wildcard configuration |

## See Also

- [auth.md](./auth.md) — Identity provider architecture
- [ports-and-dns.md](./ports-and-dns.md) — Complete port and DNS reference
- [../roadmap/stages.md](../roadmap/stages.md) — Implementation timeline