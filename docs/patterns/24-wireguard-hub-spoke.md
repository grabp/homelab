---
kind: pattern
number: 24
tags: [wireguard, vpn, hub-spoke, cgnat, nixos]
---

# Pattern 24: WireGuard hub-and-spoke on NixOS (VPS hub + routing peer + simple peers)

Raw WireGuard hub-and-spoke via a public VPS. All peers connect outbound to the VPS hub; the VPS routes between them. The routing peer (pebble) advertises a LAN subnet so mobile clients can reach all homelab services without each LAN host needing its own WireGuard config.

**Why hub-and-spoke instead of full-mesh:** pebble and boulder are behind CGNAT (symmetric NAT). Direct peer-to-peer WireGuard between a mobile device and pebble would require STUN hole-punching, which fails virtually 100% of the time on symmetric NAT. Routing everything through the VPS (public IP) bypasses this entirely — no TURN relay, no coturn, no ICE.

## WireGuard subnet: 10.10.0.0/24

```
10.10.0.1  VPS (hub, listening :51820)
10.10.0.2  pebble  (routing peer — advertises 192.168.10.0/24)
10.10.0.3  boulder (point-to-point)
10.10.0.4+ mobile clients
```

## VPS server (homelab/wireguard-server/default.nix — `my.services.wireguardServer`)

```nix
{ config, pkgs, ... }:
{
  sops.secrets."wireguard/private_key".mode = "0400";

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.10.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets."wireguard/private_key".path;

    # Re-applied on every firewall reload — postSetup alone is insufficient
    # because nixos-rebuild flushes iptables chains.
    postSetup = ''
      ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -A FORWARD -o wg0 -j ACCEPT
    '';
    postShutdown = ''
      ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -D FORWARD -o wg0 -j ACCEPT
    '';

    peers = [
      {
        # Routing peer — owns a LAN subnet behind CGNAT
        publicKey = "<pebble-pubkey>";
        allowedIPs = [ "10.10.0.2/32" "192.168.10.0/24" ];
        # No endpoint: pebble initiates; VPS learns pebble's address from handshake
      }
      {
        # Point-to-point peer — direct overlay access only
        publicKey = "<boulder-pubkey>";
        allowedIPs = [ "10.10.0.3/32" ];
      }
      {
        # Mobile client
        publicKey = "<phone-pubkey>";
        allowedIPs = [ "10.10.0.4/32" ];
      }
    ];
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  networking.firewall.allowedUDPPorts = [ 51820 ];
}
```

## Client module (homelab/wireguard-client/default.nix — `my.services.wireguardClient`)

Used by pebble (`routing = true`) and boulder (`routing = false`, default).

```nix
config = lib.mkMerge [
  (lib.mkIf cfg.enable {
    sops.secrets."wireguard/private_key".mode = "0400";

    networking.wireguard.interfaces.wg0 = {
      ips = [ cfg.address ];
      privateKeyFile = config.sops.secrets."wireguard/private_key".path;
      # No listenPort — clients use an ephemeral source port, CGNAT tracks it
      peers = [{
        publicKey = "<vps-pubkey>";
        endpoint = "${vars.vpsIP}:51820";
        allowedIPs = [ "10.10.0.0/24" ];
        persistentKeepalive = 25;  # keeps CGNAT NAT table entry alive
      }];
    };
  })

  (lib.mkIf (cfg.enable && cfg.routing) {
    # IP forwarding — required for pebble to route mobile → 192.168.10.0/24 LAN.
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # Ensure ip_forward stays enabled after firewall reloads.
    # The NixOS firewall can reset ip_forward=0 during activation, so we
    # set it via extraCommands which runs after every firewall reload.
    networking.firewall.extraCommands = ''
      echo 1 > /proc/sys/net/ipv4/ip_forward
      iptables -A FORWARD -i wg0 -j ACCEPT
      iptables -A FORWARD -o wg0 -j ACCEPT
    '';

    # Allow Loki ingestion from VPS Alloy over wg0
    networking.firewall.interfaces."wg0".allowedTCPPorts = [ 3100 ];
  })
];
```

## Mobile client config

```ini
[Interface]
Address = 10.10.0.4/32
DNS = 192.168.10.50        # Pi-hole on pebble — all DNS via tunnel while connected
PrivateKey = <device-private-key>

[Peer]
PublicKey = <vps-public-key>
Endpoint = 204.168.181.110:51820
AllowedIPs = 10.10.0.0/24, 192.168.10.0/24
PersistentKeepalive = 25
```

## Key gotchas

- **No client `listenPort`** — omitting it lets the kernel assign an ephemeral UDP port. CGNAT tracks the outbound session; incoming responses are allowed by stateful firewall rules. No inbound port needed on pebble/boulder.
- **`persistentKeepalive = 25`** — WireGuard sends a keepalive every 25 seconds to maintain the CGNAT NAT table entry. Without it, the entry expires (typically 30–120s on CGNAT) and the VPS can no longer reach pebble for routing.
- **No VPS peer endpoint for pebble/boulder** — the VPS learns the peer's source address from the first handshake packet. Since pebble/boulder always initiate, no static endpoint is needed on the VPS side.
- **Private key timing** — sops-nix decrypts secrets via activation scripts (before any systemd services start). The `wireguard-wg0.service` always finds the private key file at `/run/secrets/wireguard/private_key`. No explicit `after = [ "sops-install-secrets.service" ]` needed (that unit doesn't exist; sops uses activation scripts).
- **FORWARD rules survive firewall reloads** — `nixos-rebuild switch` flushes all iptables chains. On VPS, use `postSetup`/`postShutdown` in the wireguard interface config. On pebble, use `networking.firewall.extraCommands` which runs on every reload.
- **`ip_forward` on pebble (alphabetical sysctl trick)** — `nixos-rebuild switch` restarts `systemd-sysctl`, which re-applies all sysctl.d files in lexicographic order. `nixpkgs/nixos/modules/tasks/network-interfaces.nix` sets `net.ipv4.conf.all.forwarding = mkDefault false` → written to `/etc/sysctl.d/60-nixos.conf`. Netavark writes its `ip_forward=1` to `/run/sysctl.d/10-netavark-<id>.conf` (prefix "10" < "60"), so nixos wins and ip_forward ends up 0. Fix: set `boot.kernel.sysctl."net.ipv4.ip_forward" = 1` in the WireGuard client module. `mapAttrsToList` outputs keys alphabetically, so within `60-nixos.conf` the keys appear as: `net.ipv4.conf.all.forwarding=0` first (alphabetically), then `net.ipv4.ip_forward=1` later. Since they're kernel aliases, the last write wins. ip_forward stays 1 through the entire `systemd-sysctl` restart — no race condition, no ExecStartPost hook needed. Empirically verified on pebble (nixos-25.11).

**Source:** Verified in production (VPS + pebble + boulder, nixos-25.11) ✅
