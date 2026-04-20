{ config, lib, pkgs, vars, ... }:

let
  cfg = config.my.services.prometheus;
  blackboxPort = 9115;
  alertmanagerPort = 9093;

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
    # Telegram credentials env file — add to secrets/secrets.yaml as:
    #   alertmanager:
    #     telegram_env: |
    #       TELEGRAM_BOT_TOKEN=<bot_token_from_botfather>
    #       TELEGRAM_CHAT_ID=<chat_id>
    # systemd reads EnvironmentFile as root before dropping privileges,
    # so root ownership (sops default) is correct — no DynamicUser owner issue.
    sops.secrets."alertmanager/telegram_env" = { };

    # -------------------------------------------------------------------------
    # Alertmanager — routes Prometheus alerts to Telegram.
    # Listens on loopback only; port 9093 is not opened in the firewall.
    #
    # configText + environmentFile pattern: the alertmanager NixOS module runs
    # `envsubst` on configText in preStart, substituting $TELEGRAM_BOT_TOKEN
    # from the EnvironmentFile before alertmanager reads the config.
    # -------------------------------------------------------------------------
    services.prometheus.alertmanager = {
      enable = true;
      port = alertmanagerPort;
      listenAddress = "127.0.0.1";
      environmentFile = config.sops.secrets."alertmanager/telegram_env".path;
      # amtool check-config runs at build time but can't see environmentFile secrets,
      # so it would fail on $TELEGRAM_BOT_TOKEN. Disable build-time validation.
      checkConfig = false;

      configText = ''
        global:
          resolve_timeout: 5m

        route:
          group_by: [alertname, severity]
          group_wait: 30s
          group_interval: 5m
          repeat_interval: 12h
          receiver: telegram
          routes:
            - matchers:
                - severity=critical
              receiver: telegram
              repeat_interval: 1h

        receivers:
          - name: telegram
            telegram_configs:
              - chat_id: $TELEGRAM_CHAT_ID
                bot_token: $TELEGRAM_BOT_TOKEN
                parse_mode: HTML
                send_resolved: true
                message: |
                  {{ if eq .Status "firing" }}🔥 <b>FIRING</b>{{ else }}✅ <b>RESOLVED</b>{{ end }} — {{ .GroupLabels.alertname }}
                  {{ range .Alerts -}}
                  <b>Severity:</b> {{ .Labels.severity }}
                  {{ with .Annotations.summary -}}<b>Summary:</b> {{ . }}
                  {{ end -}}
                  {{ with .Annotations.description -}}<b>Details:</b> {{ . }}
                  {{ end -}}
                  {{ end -}}
      '';
    };

    services.prometheus = {
      enable = true;
      port = cfg.port;
      listenAddress = "127.0.0.1";
      retentionTime = "30d";

      # Tell Prometheus where Alertmanager lives.
      alertmanagers = [
        {
          static_configs = [{ targets = [ "127.0.0.1:${toString alertmanagerPort}" ]; }];
        }
      ];

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
        (pkgs.writeText "service-alerts.yml" ''
          groups:
            - name: services
              rules:
                # Fires when any systemd unit has been in failed state for 5+ minutes.
                # Requires node_exporter with enabledCollectors = ["systemd"].
                # SSH brute-force / root login / sudo alerts are implemented via
                # Loki ruler (see homelab/loki/default.nix — lokiRules).
                - alert: SystemdServiceFailed
                  expr: node_systemd_unit_state{state="failed"} == 1
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Systemd unit failed: {{ $labels.name }}"
                    description: "{{ $labels.name }} has been in a failed state for more than 5 minutes"
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
