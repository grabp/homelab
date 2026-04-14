{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

let
  cfg = config.my.services.caddy;
in
{
  options.my.services.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy with Cloudflare DNS-01";
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      # Standard pkgs.caddy lacks DNS plugins — withPlugins compiles in the
      # Cloudflare module so DNS-01 ACME challenges work without port 80 exposure.
      # Available since NixOS 25.05 via nixpkgs PR #358586.
      #
      # ⚠ FIRST BUILD: set hash = "" → run `just build` → Nix prints the correct
      #   hash in the error; paste it here and rebuild.
      # Plugin pinned to 2026-03-23 (a8737d0) — compatible with libdns v1.1.0 / Caddy 2.11.x
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.0.0-20260323191214-a8737d095ad5" ];
        hash = "sha256-LB0Y7Mc6K2h/2WfYrf3UbzCSVbvPDoK3WsBmi2Busng=";
      };

      globalConfig = ''
        email ${vars.adminEmail}
      '';

      # Wildcard cert via Cloudflare DNS-01.
      # resolvers 1.1.1.1 — bypasses Pi-hole so ACME TXT-record lookups do not
      # loop back through our own DNS, which would fail before the cert exists.
      # CLOUDFLARE_API_TOKEN is injected via EnvironmentFile (sops secret below).
      extraConfig = ''
        *.${vars.domain} {
          log {
            output stdout
            format json
          }

          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            resolvers 1.1.1.1
          }

          @pihole host pihole.${vars.domain}
          handle @pihole {
            reverse_proxy localhost:${toString config.my.services.pihole.webPort}
          }

          @vault host vault.${vars.domain}
          handle @vault {
            reverse_proxy localhost:${toString config.my.services.vaultwarden.port}
          }

          @grafana host grafana.${vars.domain}
          handle @grafana {
            reverse_proxy localhost:${toString config.my.services.grafana.port}
          }

          @prometheus host prometheus.${vars.domain}
          handle @prometheus {
            reverse_proxy localhost:${toString config.my.services.prometheus.port}
          }

          handle {
            respond "Service not found" 404
          }
        }
      '';
    };

    # caddy/env must contain: CLOUDFLARE_API_TOKEN=<token>
    # Token scopes: Zone:Zone:Read + Zone:DNS:Edit on grab-lab.gg zone.
    # Add with: just edit-secrets
    sops.secrets."caddy/env" = {
      owner = config.services.caddy.user;
      restartUnits = [ "caddy.service" ];
    };

    systemd.services.caddy.serviceConfig.EnvironmentFile = [
      config.sops.secrets."caddy/env".path
    ];

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
