# WireGuard VPN client

Hub-and-spoke WireGuard client module. Connects pebble and boulder outbound to the VPS hub. Mobile devices connect to the same VPS hub and can reach the homelab via pebble's LAN route advertisement.

## Peer assignments

| Host | WireGuard IP | Role |
|------|-------------|------|
| VPS | 10.10.0.1 | Hub (server) |
| pebble | 10.10.0.2 | Routing peer — advertises 192.168.10.0/24 |
| boulder | 10.10.0.3 | Point-to-point peer |
| Mobile device 1 | 10.10.0.4 | Client |
| (next available) | 10.10.0.5+ | Clients |

## Module options

- `my.services.wireguard.enable` — enable WireGuard client
- `my.services.wireguard.address` — WireGuard IP for this host (e.g. `"10.10.0.2/32"`)
- `my.services.wireguard.routing` — enable IP forwarding + FORWARD rules (true on pebble only)

## Adding a new mobile device

See [docs/playbooks/wireguard-add-peer.md](../../docs/playbooks/wireguard-add-peer.md).

## Server config

The VPS hub is configured in `machines/nixos/vps/wireguard.nix`.
