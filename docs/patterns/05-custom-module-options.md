---
kind: pattern
number: 5
tags: [module, options, OCI-containers]
---

# Pattern 5: Custom NixOS module with options

```nix
# homelab/pihole/default.nix
{ config, lib, pkgs, vars, ... }:

let
  cfg = config.my.services.pihole;
in
{
  options.my.services.pihole = {
    enable = lib.mkEnableOption "Pi-hole DNS sinkhole";

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8089;
      description = "Web interface port";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "pihole/pihole:2025.02.1";
      description = "Pi-hole OCI image with version tag";
    };
  };

  config = lib.mkIf cfg.enable {
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
      ];
      environment = {
        TZ = vars.timeZone;
        FTLCONF_LOCAL_IPV4 = vars.serverIP;
      };
      environmentFiles = [
        config.sops.secrets."pihole/env".path
      ];
      extraOptions = [ "--cap-add=NET_ADMIN" "--dns=127.0.0.1" ];
    };

    networking.firewall.allowedTCPPorts = [ 53 cfg.webPort ];
    networking.firewall.allowedUDPPorts = [ 53 ];

    # Disable systemd-resolved to free port 53
    services.resolved.enable = false;
  };
}
```

**Source:** NixOS Wiki module pattern + verified `virtualisation.oci-containers` option path ✅.
