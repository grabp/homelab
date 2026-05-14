# WireGuard hub server — VPS is the central peer for all homelab machines and mobile clients.
# pebble and boulder initiate outbound connections; mobile clients connect from anywhere.
# pebble advertises 192.168.10.0/24 so all homelab services are reachable via pebble.
#
# WireGuard subnet: 10.10.0.0/24
#   10.10.0.1  VPS (this host)
#   10.10.0.2  pebble  (routing peer — advertises 192.168.10.0/24)
#   10.10.0.3  boulder (point-to-point)
#   10.10.0.4+ mobile clients
#
# To add a new peer: see docs/playbooks/wireguard-add-peer.md
{
  config,
  pkgs,
  ...
}:
{
  sops.secrets."wireguard/private_key" = {
    mode = "0400";
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.10.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets."wireguard/private_key".path;

    # Allow forwarding between all wg0 peers (mobile → pebble, pebble → mobile, etc.)
    # Re-applied on every firewall reload.
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
        # pebble — routing peer, owns 192.168.10.0/24 (all homelab services)
        publicKey = "/3eOAbFMM1DdjXWCLQyO9s306vOCQrzbnoWLWj7E0AE="; # gitleaks:allow
        allowedIPs = [
          "10.10.0.2/32"
          "192.168.10.0/24"
        ];
      }
      {
        # boulder — point-to-point overlay (SSH + direct service access)
        publicKey = "mHa+5NnfhLXDDdelAVYVJfICNalopV+rjkTh6FcC3XI="; # gitleaks:allow
        allowedIPs = [ "10.10.0.3/32" ];
      }
      {
        # phone1 — 10.10.0.4
        publicKey = "ZQXuZDPUw4Qx5HOgG/d+Jh3auMBkR8DDstuOCzZweV8="; # gitleaks:allow
        allowedIPs = [ "10.10.0.4/32" ];
      }
      # Add more mobile peers here — see docs/playbooks/wireguard-add-peer.md
    ];
  };

  # WireGuard requires IP forwarding to route packets between peers.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # WireGuard listen port — must be open for inbound connections from all peers.
  networking.firewall.allowedUDPPorts = [ 51820 ];
}
