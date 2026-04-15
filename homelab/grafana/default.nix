{ config, lib, vars, ... }:

let
  cfg = config.my.services.grafana;
in
{
  options.my.services.grafana = {
    enable = lib.mkEnableOption "Grafana dashboards";
    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for Grafana web interface";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cfg.port;
          domain = "grafana.${vars.domain}";
          root_url = "https://grafana.${vars.domain}";
        };
        security = {
          admin_user = "admin";
          # $__file{...} is Grafana's native file-interpolation syntax —
          # written verbatim to grafana.ini and resolved at runtime.
          admin_password = "$__file{${config.sops.secrets."grafana/admin_password".path}}";
        };

        # Kanidm OIDC — per-client issuer URL pattern (not a global issuer).
        # auto_login = false until OIDC is verified working; flip to true after.
        "auth.generic_oauth" = {
          enabled             = true;
          name                = "Kanidm";
          client_id           = "grafana";
          client_secret       = "$__file{${config.sops.secrets."kanidm/grafana_client_secret".path}}";
          auth_url            = "https://id.${vars.domain}/ui/oauth2";
          token_url           = "https://id.${vars.domain}/oauth2/token";
          api_url             = "https://id.${vars.domain}/oauth2/openid/grafana/userinfo";
          scopes              = "openid profile email groups";
          # Kanidm returns groups as SPNs: "groupname@kanidm-domain"
          # e.g. homelab_admins@id.grab-lab.gg — not bare group names.
          role_attribute_path = "contains(groups[*], 'homelab_admins@id.${vars.domain}') && 'Admin' || 'Viewer'";
          use_pkce            = true;  # required: Kanidm 1.9 enforces PKCE by default
          allow_sign_up       = true;
          auto_login          = false;
        };
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:${toString config.my.services.prometheus.port}";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://localhost:${toString config.my.services.loki.port}";
          }
        ];
      };
    };

    # grafana/admin_password must contain the plaintext password (one line, no key=value).
    # Add with: just edit-secrets
    sops.secrets."grafana/admin_password" = {
      owner = "grafana";
      restartUnits = [ "grafana.service" ];
    };

    # kanidm/grafana_client_secret is also declared in homelab/kanidm/default.nix
    # with mode = "0444". sops-nix merges declarations — restartUnits here ensures
    # Grafana restarts when the secret is rotated.
    sops.secrets."kanidm/grafana_client_secret" = {
      mode = "0444";
      restartUnits = [ "grafana.service" ];
    };
  };
}
