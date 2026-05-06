{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.loki;

  # LogQL alert rules stored in the Nix store (read-only is fine — Loki only
  # reads from storage.local.directory). Tenant "fake" is the default when
  # auth_enabled = false.
  lokiRules = pkgs.writeTextDir "fake/security-alerts.yaml" ''
    groups:
      - name: security
        rules:
          # Fires when > 10 failed SSH auth attempts from the same source IP occur
          # in any 5-minute window. Grouped by (host, source_ip) so each attacker
          # gets a separate alert series.
          # regexp extracts `source_ip` from: "Failed ... from <ip> port <port>"
          # \S+ handles both IPv4 and IPv6 addresses.
          - alert: SSHBruteForce
            expr: |
              sum by (host, source_ip) (
                count_over_time(
                  {job="systemd-journal",unit="sshd.service"}
                  |= "Failed"
                  | regexp `from (?P<source_ip>\S+) port`
                  [5m]
                )
              ) > 10
            for: 0m
            labels:
              severity: warning
            annotations:
              summary: "SSH brute force from {{ $labels.source_ip }} on {{ $labels.host }}"
              description: "{{ $value }} failed SSH auth attempts in 5 minutes from {{ $labels.source_ip }}"

          # Fires immediately on any successful SSH login as root.
          # Extracts source IP from: "Accepted <method> for root from <ip> port <port>"
          - alert: SSHRootLogin
            expr: |
              sum by (host, source_ip) (
                count_over_time(
                  {job="systemd-journal",unit="sshd.service"}
                  |~ "Accepted .+ for root from"
                  | regexp `from (?P<source_ip>\S+) port`
                  [1m]
                )
              ) > 0
            for: 0m
            labels:
              severity: critical
            annotations:
              summary: "Root SSH login from {{ $labels.source_ip }} on {{ $labels.host }}"

          # Fires when sudo PAM authentication fails (wrong password for sudo).
          # Two guards against self-referential false positives (the ruler/Grafana log
          # their own query strings to journald, which contain the search terms):
          #   unit!="loki.service"  — excludes Loki ruler log lines at stream level
          #   |= "pam_unix(sudo"   — matches only actual PAM messages, not query text
          - alert: SudoAuthFailure
            expr: |
              count_over_time(
                {job="systemd-journal", unit!="loki.service"}
                |= "pam_unix(sudo" |= "authentication failure"
                [5m]
              ) > 0
            for: 0m
            labels:
              severity: warning
            annotations:
              summary: "Sudo auth failure on {{ $labels.host }}"
  '';
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
          # 0.0.0.0: Alloy pushers arrive on two interfaces.
          # VPS pushes over NetBird (wt0); boulder pushes over LAN (eth0).
          # Both interfaces open port 3100 — see pebble/default.nix firewall rules.
          http_listen_address = "0.0.0.0";
          http_tls_config = {
            cert_file = "/var/lib/loki/tls.pem";
            key_file = "/var/lib/loki/tls.key";
          };
        };

        common = {
          ring = {
            instance_addr = "127.0.0.1";
            kvstore.store = "inmemory";
          };
          replication_factor = 1;
          path_prefix = "/var/lib/loki";
        };

        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb"; # boltdb-shipper is deprecated; tsdb is the modern default
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];

        storage_config.filesystem.directory = "/var/lib/loki/chunks";

        limits_config = {
          retention_period = "30d";
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };

        compactor = {
          working_directory = "/var/lib/loki/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem"; # required when retention_enabled = true
        };

        # Ruler: evaluates LogQL alert rules and sends to Alertmanager.
        # Monolithic mode (default target=all) includes the ruler component.
        # storage.local.directory points to a Nix store path (read-only OK — Loki
        # only reads rule files from here). rule_path is the writable temp dir.
        ruler = {
          storage = {
            type = "local";
            local.directory = "${lokiRules}";
          };
          rule_path = "/var/lib/loki/rules-temp";
          alertmanager_url = "http://127.0.0.1:9093";
          ring.kvstore.store = "inmemory";
          enable_api = true;
          enable_alertmanager_v2 = true;
        };
      };
    };

    # -------------------------------------------------------------------------
    # Self-signed TLS cert for Loki's HTTPS listener.
    # Remote Alloy instances (VPS over NetBird, boulder over LAN) connect with
    # insecure_skip_verify = true, so the cert contents don't need to match.
    # Grafana's Loki datasource also skips verification (loopback-only call).
    # The oneshot generates once and skips if the cert already exists.
    # -------------------------------------------------------------------------
    systemd.services.loki-tls-cert = {
      description = "Generate Loki self-signed TLS certificate";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.openssl ];
      script = ''
        install -d -m 750 -o loki -g loki /var/lib/loki
        if [ ! -f /var/lib/loki/tls.pem ]; then
          openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
            -keyout /var/lib/loki/tls.key \
            -out    /var/lib/loki/tls.pem \
            -days 3650 -nodes \
            -subj '/CN=loki' \
            -addext "basicConstraints=CA:FALSE" \
            -addext "subjectAltName=IP:127.0.0.1"
          chown loki:loki /var/lib/loki/tls.key /var/lib/loki/tls.pem
          chmod 600 /var/lib/loki/tls.key
          chmod 644 /var/lib/loki/tls.pem
        fi
      '';
    };

    # Hard-order: loki cannot start until the cert is present.
    systemd.services.loki = {
      requires = [ "loki-tls-cert.service" ];
      after = [ "loki-tls-cert.service" ];
    };

    systemd.tmpfiles.rules = [
      # Loki ruler temp dir — writable scratch space for compiled rule evaluation.
      "d /var/lib/loki/rules-temp 0750 loki  loki  -"
    ];

    networking.firewall.allowedTCPPorts = [
      # Open port 3100 so boulder is able to push logs
      3100
    ];

    # Ship this machine's systemd journal to the local Loki instance via the shared alloy module.
    my.services.alloy = {
      enable = true;
      hostLabel = config.networking.hostName;
      lokiUrl = "https://localhost:${toString cfg.port}/loki/api/v1/push";
      insecureSkipVerify = true;
    };
  };
}
