# homelab/homepage/default.nix — Homepage dashboard (Stage 8)
#
# Native NixOS module: services.homepage-dashboard
# Port: 3010 (remapped from default 3000 to avoid Grafana conflict)
# URL: https://home.grab-lab.gg
# Auth: oauth2-proxy (port 4180) in front of Homepage, Kanidm as OIDC backend.
#       Caddy → oauth2-proxy:4180 → Homepage:3010
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

    oauth2ProxyPort = lib.mkOption {
      type    = lib.types.port;
      default = 4180;
      description = "oauth2-proxy listen port — Caddy proxies here, oauth2-proxy proxies to Homepage";
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
            {
              "ESPHome" = {
                href        = "https://esphome.${vars.domain}";
                description = "ESP device dashboard";
                icon        = "esphome.svg";
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

    # ── oauth2-proxy ─────────────────────────────────────────────────────────
    # Sits between Caddy and Homepage. Handles the PKCE OAuth2 dance with
    # Kanidm, issues a session cookie, then proxies authenticated requests to
    # Homepage. Unauthenticated requests are redirected to Kanidm login.
    #
    # --network=host: both the upstream (localhost:3010) and the bind address
    # (127.0.0.1:4180) live on the host network stack.
    #
    # No Netavark/firewall fix needed: host networking has no port-publish DNAT
    # rules to lose when firewall.service reloads.
    virtualisation.oci-containers.containers.oauth2-proxy-homepage = {
      image = "quay.io/oauth2-proxy/oauth2-proxy:v7.8.1";
      # --upstream passed as a CLI arg: oauth2-proxy v7.8.1 does not reliably
      # pick up OAUTH2_PROXY_UPSTREAM from the environment (Viper mapping issue).
      # Trailing slash is required — bare host:port is rejected by the URL parser.
      cmd = [ "--upstream=http://127.0.0.1:${toString cfg.port}/" ];
      environment = {
        # Kanidm per-client OIDC discovery:
        # https://id.DOMAIN/oauth2/openid/homepage/.well-known/openid-configuration
        OAUTH2_PROXY_PROVIDER              = "oidc";
        OAUTH2_PROXY_OIDC_ISSUER_URL       = "https://id.${vars.domain}/oauth2/openid/homepage";
        OAUTH2_PROXY_CLIENT_ID             = "homepage";
        OAUTH2_PROXY_REDIRECT_URL          = "https://home.${vars.domain}/oauth2/callback";
        OAUTH2_PROXY_HTTP_ADDRESS          = "127.0.0.1:${toString cfg.oauth2ProxyPort}";
        OAUTH2_PROXY_EMAIL_DOMAINS         = "*";  # Kanidm email is optional; allow any domain
        OAUTH2_PROXY_SCOPE                 = "openid profile email";
        OAUTH2_PROXY_CODE_CHALLENGE_METHOD = "S256";  # PKCE — required by Kanidm 1.9
        OAUTH2_PROXY_SKIP_PROVIDER_BUTTON  = "true";  # auto-redirect to Kanidm, no button page
        OAUTH2_PROXY_COOKIE_SECURE         = "true";
        OAUTH2_PROXY_COOKIE_SAMESITE       = "lax";
      };
      # OAUTH2_PROXY_CLIENT_SECRET and OAUTH2_PROXY_COOKIE_SECRET injected here.
      environmentFiles = [ config.sops.secrets."oauth2-proxy/homepage_env".path ];
      extraOptions = [ "--network=host" ];
    };

    # oauth2-proxy/homepage_env must contain:
    #   OAUTH2_PROXY_CLIENT_SECRET=<same value as kanidm/homepage_client_secret>
    #   OAUTH2_PROXY_COOKIE_SECRET=<openssl rand -hex 16>  ← must be exactly 32 chars
    # Add with: just edit-secrets
    sops.secrets."oauth2-proxy/homepage_env" = { };
  };
}
