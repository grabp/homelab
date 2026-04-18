# homelab/uptime-kuma/default.nix — Uptime Kuma service monitor (Stage 9a)
#
# Native NixOS module: services.uptime-kuma
# Port: 3001/tcp (localhost only — proxied via Caddy)
# Auth: Uptime Kuma has its own internal login. Set up admin account on first visit.
#       Optional: add Caddy forward_auth via Kanidm (Pattern 22) as an extra layer.
#
# State: SQLite database in /var/lib/uptime-kuma/ — persisted across reboots.
{ config, lib, ... }:

let
  cfg = config.my.services.uptimeKuma;
in
{
  options.my.services.uptimeKuma = {
    enable = lib.mkEnableOption "Uptime Kuma service monitor";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 3001;
      description = "Uptime Kuma listen port (localhost only)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.uptime-kuma = {
      enable   = true;
      settings = {
        PORT = toString cfg.port;
        HOST = "127.0.0.1";
      };
    };

    # Uptime Kuma is proxied through Caddy — no direct firewall exposure needed.
    # (Port is bound to 127.0.0.1 above.)
  };
}
