# WireGuard VPN hub server

Hub-and-spoke WireGuard server module. Runs on the VPS (public IP). All peers connect outbound to this hub; the VPS routes between them.

## Peer assignments

| Host | WireGuard IP | Role |
|------|-------------|------|
| VPS | 10.10.0.1 | Hub (this host, listening :51820) |
| pebble | 10.10.0.2 | Routing peer — advertises 192.168.10.0/24 |
| boulder | 10.10.0.3 | Point-to-point peer |
| Mobile device 1 | 10.10.0.4 | Client |
| (next available) | 10.10.0.5+ | Clients |

## Module options

- `my.services.wireguardServer.enable` — enable WireGuard hub server

## Adding a new peer

See [docs/playbooks/wireguard-add-peer.md](../../docs/playbooks/wireguard-add-peer.md).

## Client config

Spoke machines (pebble, boulder) use `homelab/wireguard-client/` (`my.services.wireguardClient`).
