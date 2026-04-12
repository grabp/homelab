{ config, lib, pkgs, vars, ... }:

let
  cfg = config.my.services.pihole;

  # Wildcard split DNS: *.grab-lab.gg → Caddy on serverIP
  # Mounted read-only into the container at /etc/dnsmasq.d/
  dnsmasqConf = pkgs.writeText "04-grab-lab.conf" ''
    address=/${vars.domain}/${vars.serverIP}
  '';
in
{
  options.my.services.pihole = {
    enable = lib.mkEnableOption "Pi-hole DNS sinkhole";

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8089;
      description = "Host port for the Pi-hole web UI (mapped to container port 80)";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "pihole/pihole:2025.02.1";
      description = "Pi-hole OCI image with version tag";
    };
  };

  config = lib.mkIf cfg.enable {
    # FTLCONF_webserver_api_password=<password> — add to secrets/secrets.yaml
    sops.secrets."pihole/env" = { };

    # Persistent ZFS-backed directories for Pi-hole state
    systemd.tmpfiles.rules = [
      "d /var/lib/pihole/etc-pihole    0755 root root -"
      "d /var/lib/pihole/etc-dnsmasq.d 0755 root root -"
    ];

    virtualisation.oci-containers.containers.pihole = {
      image = cfg.image;

      ports = [
        "53:53/tcp"
        "53:53/udp"
        "${toString cfg.webPort}:80/tcp"
      ];

      volumes = [
        "/var/lib/pihole/etc-pihole:/etc/pihole"
        "/var/lib/pihole/etc-dnsmasq.d:/etc/dnsmasq.d"
        # Inject wildcard DNS config from Nix store — declarative, survives redeployment
        "${dnsmasqConf}:/etc/dnsmasq.d/04-grab-lab.conf:ro"
      ];

      environment = {
        TZ = vars.timeZone;
        FTLCONF_LOCAL_IPV4 = vars.serverIP;
      };

      # Contains FTLCONF_webserver_api_password — decrypted by sops at /run/secrets/pihole/env
      environmentFiles = [
        config.sops.secrets."pihole/env".path
      ];

      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--dns=127.0.0.1"  # Container resolves via itself (avoids DNS loop on startup)
      ];
    };

    networking.firewall.allowedTCPPorts = [ 53 cfg.webPort ];
    networking.firewall.allowedUDPPorts = [ 53 ];

    # Must be disabled — systemd-resolved holds port 53 by default
    # Stage 6b (NetBird) re-enables resolved with DNSStubListener=no
    services.resolved.enable = false;
  };
}
