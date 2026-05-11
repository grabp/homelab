# homelab/calibre-web-automated/default.nix — Calibre-Web Automated e-book library (OCI)
#
# Single OCI container. No Redis or PostgreSQL — SQLite only.
# Books placed in /var/lib/calibre-web-automated/ingest/ are auto-ingested and deleted.
#
# Proxied by Caddy on pebble: https://books.grab-lab.gg → boulderIP:8083
#
# PRE-DEPLOY:
#   just edit-secrets-boulder → add calibre-web-automated/hardcover_token:
#     "HARDCOVER_TOKEN=<your_hardcover_api_key>"  (env-file format)
#   just edit-secrets-pebble  → add kanidm/calibre_web_client_secret: "<strong_random_secret>"
{
  config,
  lib,
  vars,
  ...
}:

let
  cfg = config.my.services.calibreWebAutomated;
in
{
  options.my.services.calibreWebAutomated = {
    enable = lib.mkEnableOption "Calibre-Web Automated e-book library";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8083;
      description = "CWA host port (Caddy on pebble proxies here).";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Sops secret: Hardcover API token as env file ──────────────────────────
    # Format: HARDCOVER_TOKEN=<api_key>  (env-file key=value, not the raw key)
    sops.secrets."calibre-web-automated/hardcover_token" = {
      mode = "0400";
    };

    # ── Storage directories owned by container UID 1000 ───────────────────────
    systemd.tmpfiles.rules = [
      "d /var/lib/calibre-web-automated         0750 1000 1000 -"
      "d /var/lib/calibre-web-automated/config  0750 1000 1000 -"
      "d /var/lib/calibre-web-automated/ingest  0750 1000 1000 -"
      "d /var/lib/calibre-web-automated/library 0750 1000 1000 -"
    ];

    # ── Calibre-Web Automated ─────────────────────────────────────────────────
    virtualisation.oci-containers.containers.calibre-web-automated = {
      image = "docker.io/crocodilestick/calibre-web-automated:latest@sha256:fbf0c866e77b366f07050a6a12fee4e840b60d364485576a810109851a488eec";
      ports = [ "0.0.0.0:${toString cfg.port}:8083" ];
      # Disable the image's built-in healthcheck. It fires within milliseconds of
      # container start (before CWA initialises), causing the transient Podman
      # healthcheck systemd unit to fail and triggering a deploy-rs rollback.
      extraOptions = [ "--no-healthcheck" ];
      volumes = [
        "/var/lib/calibre-web-automated/config:/config"
        "/var/lib/calibre-web-automated/ingest:/cwa-book-ingest"
        "/var/lib/calibre-web-automated/library:/calibre-library"
      ];
      environmentFiles = [ config.sops.secrets."calibre-web-automated/hardcover_token".path ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = vars.timeZone;
        # Required when running behind Caddy — prevents "Session protection
        # triggered" errors caused by mismatched forwarded IP headers.
        TRUSTED_PROXY_COUNT = "1";
        NETWORK_SHARE_MODE = "false";
      };
    };

    # Pattern 19: NixOS firewall reload flushes Netavark DNAT rules — restart
    # container so port mappings are re-registered.
    systemd.services.podman-calibre-web-automated = {
      after = [ "firewall.service" ];
      partOf = [ "firewall.service" ];
    };

    # ── Firewall: LAN (eth0) access for Caddy on pebble ───────────────────────
    networking.firewall.interfaces."eth0".allowedTCPPorts = [ cfg.port ];
  };
}
