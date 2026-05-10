{
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.my.services.netbird;
in
{
  imports = [ ./restart-timer.nix ];

  options.my.services.netbird = {
    enable = lib.mkEnableOption "NetBird VPN client";
    routing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable IP forwarding and route advertisement. Set false on hosts that only need point-to-point overlay access (e.g. VPS).";
    };
  };

  config = lib.mkMerge [
    {
      # nixos-25.11 ships netbird 0.60.2 which is protocol-incompatible with the
      # 0.68.x management server. Override with unstable to match the server version.
      nixpkgs.overlays = [
        (final: prev: {
          inherit (inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.system}) netbird;
        })
      ];
    }

    (lib.mkIf cfg.enable {
      # Setup key — available at /run/secrets/netbird/setup_key for the one-time
      # manual login step after first deploy. Not used by a login service (the
      # netbird-wt0-login oneshot is unreliable during nixos-rebuild switch due
      # to a race with the daemon socket; once registered, state persists in
      # /var/lib/netbird-wt0/ and the daemon reconnects automatically).
      sops.secrets."netbird/setup_key" = { };

      # NetBird client configuration
      services.netbird.clients.wt0 = {
        port = 51820;
        openFirewall = true;
        ui.enable = false;
        # ManagementURL is NOT set here: netbird 0.60.2 stores it as url.URL (Go
        # struct), so writing it as a JSON string in 50-nixos.json causes
        # "cannot unmarshal string into Go struct field Config.ManagementURL of
        # type url.URL" and the daemon fails to start. Set it once via CLI on
        # first login; netbird persists it in /var/lib/netbird-wt0/config.json.
      };

      # Allow UDP 51820 for WireGuard
      networking.firewall.allowedUDPPorts = [ 51820 ];

      # IP forwarding + FORWARD rules — only needed on routing peers (pebble, boulder).
      # VPS sets routing = false: it only needs point-to-point overlay access to pebble.
      services.netbird.useRoutingFeatures = lib.mkIf cfg.routing "both";
      networking.firewall.extraCommands = lib.mkIf cfg.routing ''
        iptables -A FORWARD -i wt0 -j ACCEPT
        iptables -A FORWARD -o wt0 -j ACCEPT
      '';
    })
  ];
}
