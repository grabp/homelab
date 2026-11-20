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
      image = "ghcr.io/stirling-tools/stirling-pdf:3.4.0@sha256:25258985ef89720f332752b0b84f86b5ffa3b73caf355dfc028c0a59648ff4f3";
      ports = [ "0.0.0.0:${toString cfg.port}:8080" ];
      volumes = [ "/var/lib/stirling-pdf:/configs" ];
      environment = {
        # v1+ env names: DOCKER_ENABLE_SECURITY → DISABLE_ADDITIONAL_FEATURES
        # (no login/security jar); LANGS and INSTALL_BOOK_AND_ADVANCED_HTML_OPS
        # are no longer read by the standard image.
        DISABLE_ADDITIONAL_FEATURES = "true";
        SECURITY_ENABLELOGIN = "false";
        SYSTEM_DEFAULTLOCALE = "en-GB";
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
