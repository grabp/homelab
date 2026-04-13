{ config, lib, ... }:

let
  cfg = config.my.services.prometheus;
in
{
  options.my.services.prometheus = {
    enable = lib.mkEnableOption "Prometheus metrics collection";
    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for Prometheus HTTP API";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;
      listenAddress = "127.0.0.1";
      retentionTime = "30d";

      exporters.node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
        # Listens on 127.0.0.1:9100 by default
      };

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
          }];
        }
      ];
    };
  };
}
