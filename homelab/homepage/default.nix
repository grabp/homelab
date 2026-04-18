# homelab/homepage/default.nix — Homepage dashboard (Stage 8)
#
# Native NixOS module: services.homepage-dashboard
# Port: 3010 (remapped from default 3000 to avoid Grafana conflict)
# URL: https://home.grab-lab.gg
# Auth: Homepage has no native auth. Add Caddy forward_auth via Kanidm
#       (Pattern 22) once verified — see ⚠️ note in docs/NIX-PATTERNS.md.
{ config, lib, vars, ... }:

let
  cfg = config.my.services.homepage;
in
{
  options.my.services.homepage = {
    enable = lib.mkEnableOption "Homepage dashboard";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 3010;
      description = "Listen port — remapped from 3000 to avoid Grafana conflict";
    };
  };

  config = lib.mkIf cfg.enable {
    services.homepage-dashboard = {
      enable     = true;
      listenPort = cfg.port;

      # allowedHosts: required when accessed via a reverse proxy hostname
      allowedHosts = "home.${vars.domain}";

      settings = {
        title       = "Homelab";
        headerStyle = "clean";
        target      = "_blank";
        color       = "slate";
      };

      services = [
        {
          "Infrastructure" = [
            {
              "Pi-hole" = {
                href        = "https://pihole.${vars.domain}/admin";
                description = "DNS sinkhole";
                icon        = "pi-hole.svg";
              };
            }
            {
              "Caddy" = {
                description = "Reverse proxy + TLS";
                icon        = "caddy.svg";
              };
            }
          ];
        }
        {
          "Security" = [
            {
              "Vaultwarden" = {
                href        = "https://vault.${vars.domain}";
                description = "Password manager";
                icon        = "vaultwarden.svg";
              };
            }
            {
              "Kanidm" = {
                href        = "https://id.${vars.domain}";
                description = "Identity provider (OIDC + LDAP)";
                icon        = "kanidm.svg";
              };
            }
          ];
        }
        {
          "Monitoring" = [
            {
              "Grafana" = {
                href        = "https://grafana.${vars.domain}";
                description = "Dashboards";
                icon        = "grafana.svg";
              };
            }
            {
              "Prometheus" = {
                href        = "https://prometheus.${vars.domain}";
                description = "Metrics";
                icon        = "prometheus.svg";
              };
            }
            {
              "Uptime Kuma" = {
                href        = "https://uptime.${vars.domain}";
                description = "Service monitor";
                icon        = "uptime-kuma.svg";
              };
            }
          ];
        }
        {
          "Home Automation" = [
            {
              "Home Assistant" = {
                href        = "https://ha.${vars.domain}";
                description = "Home automation";
                icon        = "home-assistant.svg";
              };
            }
          ];
        }
        {
          "Networking" = [
            {
              "NetBird" = {
                href        = "https://netbird.${vars.domain}";
                description = "VPN control plane (VPS)";
                icon        = "netbird.svg";
              };
            }
          ];
        }
      ];

      bookmarks = [
        {
          "Admin" = [
            { "Flake repo"    = [{ href = "https://github.com/grabp/homelab"; }]; }
            { "Cloudflare"    = [{ href = "https://dash.cloudflare.com"; }]; }
            { "Hetzner Cloud" = [{ href = "https://console.hetzner.cloud"; }]; }
          ];
        }
      ];
    };
  };
}
