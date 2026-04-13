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
  };
}
