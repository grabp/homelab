{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

let
  cfg = config.my.services.wireguardClient;
in
{
  options.my.services.wireguardClient = {
    enable = lib.mkEnableOption "WireGuard VPN client";

    address = lib.mkOption {
      type = lib.types.str;
      description = "WireGuard IP for this host, e.g. \"10.10.0.2/32\".";
    };

    routing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable IP forwarding and iptables FORWARD rules. True on pebble (advertises 192.168.10.0/24 to the mesh); false on boulder (point-to-point overlay only).";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      sops.secrets."wireguard/private_key" = {
        mode = "0400";
      };

      networking.wireguard.interfaces.wg0 = {
        ips = [ cfg.address ];
        privateKeyFile = config.sops.secrets."wireguard/private_key".path;

        peers = [
          {
            # VPS hub — all overlay traffic routes through here.
            # pebble and boulder initiate outbound; PersistentKeepalive keeps the
            # CGNAT mapping open so the VPS can always reach back.
            publicKey = "Va6gsgUqcxtgW8wLNCiBGVv+dr3xe9J27pbniMRHExU="; # gitleaks:allow
            endpoint = "${vars.vpsIP}:51820";
            allowedIPs = [ "10.10.0.0/24" ];
            persistentKeepalive = 25;
          }
        ];
      };
    })

    (lib.mkIf (cfg.enable && cfg.routing) {
      # IP forwarding — required for pebble to route mobile → 192.168.10.0/24 LAN.
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

      # Allow forwarded packets in and out of the WireGuard interface.
      # Re-applied on every firewall reload (firewall flushes all chains on rebuild).
      # Also ensure ip_forward stays enabled after firewall resets it.
      networking.firewall.extraCommands = ''
        echo 1 > /proc/sys/net/ipv4/ip_forward
        iptables -A FORWARD -i wg0 -j ACCEPT
        iptables -A FORWARD -o wg0 -j ACCEPT
      '';

      # Loki ingestion port — VPS Alloy pushes logs over wg0 to pebble's Loki.
      # Only pebble (routing = true) runs Loki; boulder does not.
      networking.firewall.interfaces."wg0".allowedTCPPorts = [ 3100 ];
    })
  ];
}
