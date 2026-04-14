# Caddy reverse proxy for NetBird control plane on VPS.
# HTTP-01 ACME challenge works here (public IP) — no Cloudflare DNS plugin needed.
# Caddy proxies gRPC natively via h2c:// (cleartext HTTP/2 to backend).
{ vars, ... }:

let
  domain = "netbird.${vars.domain}";
in
{
  services.caddy = {
    enable = true;
    globalConfig = ''
      email ${vars.adminEmail}
    '';

    virtualHosts."${domain}".extraConfig = ''
      # Management REST API
      handle /api/* {
        reverse_proxy localhost:8080
      }

      # Management gRPC — h2c = cleartext HTTP/2, required for gRPC to backend
      handle /management.ManagementService/* {
        reverse_proxy h2c://localhost:8080
      }

      # Signal gRPC — separate netbirdio/signal container on port 10000
      handle /signalexchange.SignalExchange/* {
        reverse_proxy h2c://localhost:10000
      }

      # Embedded Dex IdP — OAuth2/OIDC endpoints served by management container
      handle /oauth2/* {
        reverse_proxy localhost:8080
      }

      # Dashboard SPA — catch-all
      handle {
        reverse_proxy localhost:3000
      }
    '';
  };
}
