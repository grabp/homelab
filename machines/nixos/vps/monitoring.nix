{ ... }:
{
  services.alloy = {
    enable = true;
    configPath = "/etc/alloy/config.alloy";
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.source.journal "vps_journal" {
      max_age       = "12h"
      relabel_rules = loki.relabel.vps_labels.rules
      forward_to    = [loki.write.pebble.receiver]
    }

    loki.relabel "vps_labels" {
      forward_to = []
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        replacement  = "vps"
        target_label = "host"
      }
      rule {
        replacement  = "systemd-journal"
        target_label = "job"
      }
    }

    loki.write "pebble" {
      endpoint {
        # pebble NetBird overlay IP (verified Stage 7b: just netbird-status)
        url = "http://100.102.154.38:3100/loki/api/v1/push"
      }
    }
  '';

  # Alloy needs a writable state dir for its WAL (write-ahead log).
  # Same precaution as the promtail 226/NAMESPACE fix on pebble.
  systemd.tmpfiles.rules = [
    "d /var/lib/alloy 0750 alloy alloy -"
  ];
}
