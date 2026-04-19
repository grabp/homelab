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
          # 0.0.0.0: required so VPS Alloy can push over the NetBird wt0 interface.
          # Port 3100 is blocked on eth0 (LAN) via the firewall — only wt0 is opened.
          # See: networking.firewall.interfaces."wt0".allowedTCPPorts in pebble/default.nix
          http_listen_address = "0.0.0.0";
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

    # Alloy state directory (WAL, positions).
    # Added as a precaution — same pattern as the promtail 226/NAMESPACE fix.
    systemd.tmpfiles.rules = [
      "d /var/lib/alloy 0750 alloy alloy -"
    ];

    # Alloy ships systemd-journal logs to Loki (replaces EOL Promtail, 2026-03-02).
    # Uses River/Alloy syntax (.alloy files), not YAML.
    services.alloy = {
      enable = true;
      configPath = "/etc/alloy/config.alloy";
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.source.journal "journal" {
        max_age       = "12h"
        relabel_rules = loki.relabel.labels.rules
        forward_to    = [loki.write.local.receiver]
      }

      loki.relabel "labels" {
        forward_to = []
        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
        rule {
          replacement  = "pebble"
          target_label = "host"
        }
        rule {
          replacement  = "systemd-journal"
          target_label = "job"
        }
      }

      loki.write "local" {
        endpoint {
          url = "http://localhost:${toString cfg.port}/loki/api/v1/push"
        }
      }
    '';
  };
}
