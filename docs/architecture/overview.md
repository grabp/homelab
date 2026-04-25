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
| **vps** | NetBird control plane, Pocket ID IdP, public entry point | Hetzner CX22 | 204.168.181.110 (public) | NixOS 25.11, ext4 |
| **boulder** | Future media server, document management | HP EliteDesk (planned) | 192.168.10.51/24 (LAN) | NixOS 25.11, ZFS |

## Network Topology

```
Internet → (blocked to homelab — no port forwards, CGNAT)

LAN clients → Pi-hole (DNS :53) → resolves *.grab-lab.gg → 192.168.10.50
                                 → Caddy (:443) → localhost:<service-port>

VPN peers (phone/laptop)
  → TCP 443 / UDP 3478 → VPS (netbird.grab-lab.gg, public IP)
      ↕ relay or P2P WireGuard (encrypted end-to-end)
  ← pebble (behind CGNAT, outbound-only to VPS)
  → NetBird DNS: *.grab-lab.gg match-domain → Pi-hole overlay IP → Caddy → service

pebble ← ISP CGNAT (symmetric NAT, no inbound) ← VPS relay ← VPN peer
         (P2P hole-punch if CGNAT maps consistently; relay otherwise ~7 Mbps / ~85ms)
```

### CGNAT Implications

The homelab's ISP uses symmetric NAT (Endpoint-Dependent Mapping). STUN hole-punching fails virtually 100% of the time, so VPN peers almost always relay through the VPS via WireGuard.

**Relay performance:** ~7 Mbps throughput, ~85ms latency — adequate for dashboards and media at moderate quality.

**Known issue (stale relay, GitHub #3936):** Behind CGNAT, NetBird can show "Connected" but stop passing traffic. Workaround: `netbird-wt0 down && netbird-wt0 up` or restart the systemd service.

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

NetBird VPN clients use a split DNS nameserver: queries for `*.grab-lab.gg` go to Pi-hole via the VPN tunnel; all other queries go to public resolvers.

## VPS as Public Entry Point

The VPS is the only externally reachable endpoint. It runs:

| Service | Purpose |
|---------|---------|
| NetBird control plane | Management API, Signal, Dashboard, Relay |
| Pocket ID | Passkey-only OIDC provider for NetBird auth |
| Caddy | TLS termination for Pocket ID |

The VPS never sees decrypted VPN traffic — WireGuard provides end-to-end encryption between peers.

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