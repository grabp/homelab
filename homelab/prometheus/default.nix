{ config, lib, pkgs, vars, ... }:

let
  cfg = config.my.services.prometheus;
  blackboxPort = 9115;

  # All public HTTPS endpoints probed for TLS cert validity and HTTP reachability.
  # Services behind oauth2-proxy return 302; follow_redirects=true keeps probe_success=1
  # while probe_ssl_earliest_cert_expiry still tracks the cert from the first TLS handshake.
  httpsTargets = [
    "https://pihole.${vars.domain}"
    "https://vault.${vars.domain}"
    "https://prometheus.${vars.domain}"
    "https://grafana.${vars.domain}"
    "https://id.${vars.domain}"
    "https://home.${vars.domain}"
    "https://ha.${vars.domain}"
    "https://uptime.${vars.domain}"
    "https://esphome.${vars.domain}"
    "https://netbird.${vars.domain}"
    "https://pocket-id.${vars.domain}"
  ];
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

      # Blackbox exporter: probes HTTPS endpoints for cert expiry and HTTP reachability.
      # Binds to loopback only — no firewall change needed.
      exporters.blackbox = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = blackboxPort;
        configFile = pkgs.writeText "blackbox.yml" ''
          modules:
            http_2xx:
              prober: http
              timeout: 15s
              http:
                valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
                method: GET
                follow_redirects: true
                preferred_ip_protocol: "ip4"
                tls_config:
                  insecure_skip_verify: false
        '';
      };

      # Alert rules — fire in Prometheus now; routed by Alertmanager in the next TODO.
      ruleFiles = [
        (pkgs.writeText "tls-alerts.yml" ''
          groups:
            - name: tls
              rules:
                - alert: TLSCertExpiringSoon
                  expr: probe_ssl_earliest_cert_expiry{job="tls_probe"} - time() < 86400 * 30
                  for: 1h
                  labels:
                    severity: warning
                  annotations:
                    summary: "TLS cert expiring soon on {{ $labels.instance }}"
                    description: "Certificate expires in {{ humanizeDuration $value }}"
                - alert: TLSCertExpired
                  expr: probe_ssl_earliest_cert_expiry{job="tls_probe"} - time() < 0
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: "TLS cert EXPIRED on {{ $labels.instance }}"
        '')
      ];

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
          }];
        }
        # Multi-target blackbox pattern: Prometheus rewrites __address__ to __param_target
        # so each target URL is passed to the exporter as a probe request.
        {
          job_name = "tls_probe";
          metrics_path = "/probe";
          params.module = [ "http_2xx" ];
          static_configs = [{ targets = httpsTargets; }];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "127.0.0.1:${toString blackboxPort}";
            }
          ];
        }
      ];
    };
  };
}
