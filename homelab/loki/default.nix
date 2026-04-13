{ config, lib, ... }:

let
  cfg = config.my.services.loki;
in
{
  options.my.services.loki = {
    enable = lib.mkEnableOption "Loki log aggregation";
    port = lib.mkOption {
      type = lib.types.port;
      default = 3100;
      description = "Port for Loki HTTP API";
    };
  };

  config = lib.mkIf cfg.enable {
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_port = cfg.port;
          http_listen_address = "127.0.0.1";
        };

        common = {
          ring = {
            instance_addr = "127.0.0.1";
            kvstore.store = "inmemory";
          };
          replication_factor = 1;
          path_prefix = "/var/lib/loki";
        };

        schema_config.configs = [{
          from = "2024-01-01";
          store = "tsdb";          # boltdb-shipper is deprecated; tsdb is the modern default
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];

        storage_config.filesystem.directory = "/var/lib/loki/chunks";

        limits_config = {
          retention_period = "30d";
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };

        compactor = {
          working_directory = "/var/lib/loki/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";  # required when retention_enabled = true
        };
      };
    };

    # /var/lib/promtail must exist before the service starts: the NixOS module sets
    # PrivateMounts=true + ReadWritePaths=/var/lib/promtail, so systemd bind-mounts
    # that path into the private namespace at startup — if it's absent the namespace
    # setup fails with 226/NAMESPACE before the pre-start script runs.
    systemd.tmpfiles.rules = [
      "d /var/lib/promtail 0750 promtail promtail -"
    ];

    # Promtail ships systemd-journal logs to Loki
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 3031;
          grpc_listen_port = 0;
        };
        positions.filename = "/var/lib/promtail/positions.yaml";
        clients = [{ url = "http://localhost:${toString cfg.port}/loki/api/v1/push"; }];
        scrape_configs = [{
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = {
              job = "systemd-journal";
              host = "pebble";
            };
          };
          relabel_configs = [{
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }];
        }];
      };
    };
  };
}
