# homelab/stirling-pdf/default.nix — Stirling-PDF toolkit
#
# Stateless OCI container for PDF operations (merge, split, compress, convert).
# No database or persistent state — only a /configs volume for optional settings.
#
# Proxied by Caddy on pebble: https://pdf.grab-lab.gg → boulderIP:8080
{
  config,
  lib,
  vars,
  ...
}:

let
  cfg = config.my.services.stirlingPdf;
in
{
  options.my.services.stirlingPdf = {
    enable = lib.mkEnableOption "Stirling-PDF toolkit";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Stirling-PDF web port (referenced by Caddy on pebble).";
    };
  };

  config = lib.mkIf cfg.enable {

    systemd.tmpfiles.rules = [
      "d /var/lib/stirling-pdf 0750 root root -"
    ];

    virtualisation.oci-containers.containers.stirling-pdf = {
      image = "ghcr.io/stirling-tools/stirling-pdf:0.42.0@sha256:eb8684f6b9e9af7e0323fc4d6bc193f8a0f12a2b52544292a2aebab60992c4f0";
      ports = [ "0.0.0.0:${toString cfg.port}:8080" ];
      volumes = [ "/var/lib/stirling-pdf:/configs" ];
      environment = {
        DOCKER_ENABLE_SECURITY = "false";
        INSTALL_BOOK_AND_ADVANCED_HTML_OPS = "false";
        LANGS = "en_GB pl_PL";
      };
    };

    # Pattern 19: NixOS firewall reload flushes Netavark DNAT rules — restart
    # the container so its port mappings are re-registered.
    systemd.services.podman-stirling-pdf = {
      after = [ "firewall.service" ];
      partOf = [ "firewall.service" ];
    };

    # Firewall: LAN (eth0) access for Caddy on pebble
    networking.firewall.interfaces."eth0".allowedTCPPorts = [ cfg.port ];
  };
}
