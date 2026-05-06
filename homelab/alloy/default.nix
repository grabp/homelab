{ config, lib, ... }:

let
  cfg = config.my.services.alloy;
in
{
  options.my.services.alloy = {
    enable = lib.mkEnableOption "Grafana Alloy — ship systemd journal to pebble Loki";

    hostLabel = lib.mkOption {
      type = lib.types.str;
      description = "Value for the 'host' label attached to all log streams (e.g. \"vps\" or \"boulder\")";
    };

    lokiUrl = lib.mkOption {
      type = lib.types.str;
      description = "Loki push endpoint URL. Use NetBird overlay IP for machines not on pebble's LAN; use pebbleIP directly for LAN-adjacent machines.";
      example = "http://100.102.154.38:3100/loki/api/v1/push";
    };

    insecureSkipVerify = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip TLS certificate verification when pushing to Loki. Safe for self-signed certs on private networks.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.alloy = {
      enable = true;
      configPath = "/etc/alloy/config.alloy";
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.source.journal "journal" {
        max_age       = "12h"
        relabel_rules = loki.relabel.labels.rules
        forward_to    = [loki.write.pebble.receiver]
      }

      loki.relabel "labels" {
        forward_to = []
        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
        rule {
          replacement  = "${cfg.hostLabel}"
          target_label = "host"
        }
        rule {
          replacement  = "systemd-journal"
          target_label = "job"
        }
      }

      loki.write "pebble" {
        endpoint {
          url = "${cfg.lokiUrl}"
          ${lib.optionalString cfg.insecureSkipVerify ''
            tls_config {
              insecure_skip_verify = true
            }''}
        }
      }
    '';

    # Alloy needs a writable state dir for its WAL (write-ahead log).
    systemd.tmpfiles.rules = [
      "d /var/lib/alloy 0750 alloy alloy -"
    ];
  };
}
