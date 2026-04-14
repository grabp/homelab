{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

let
  cfg = config.my.services.netbird;
  domain = "netbird.${vars.domain}";

  # Zitadel Cloud IdP
  zitadelIssuer = "https://grablab-zitadel-cloud-70oyna.eu1.zitadel.cloud";
  zitadelClientId = "368487648114824331";
  zitadelProjectId = "368487538106567602"; # audience in JWT tokens

  # management.json template — secrets (TURN password, encryption key) are
  # injected at runtime by the netbird-management-config systemd oneshot.
  mgmtConfigTemplate = pkgs.writeText "management.json.tmpl" (
    builtins.toJSON {
      Stuns = [
        {
          Proto = "udp";
          URI = "${domain}:3478";
          Username = null;
          Password = null;
        }
      ];
      TURNConfig = {
        Turns = [
          {
            Proto = "udp";
            URI = "turn:${domain}:3478";
            Username = "netbird";
            Password = "TURN_PLACEHOLDER";
          }
        ];
        CredentialsTTL = "12h";
        Secret = "TURN_PLACEHOLDER";
        TimeBasedCredentials = false;
      };
      Signal = {
        Proto = "https";
        URI = "${domain}:443";
        Username = null;
        Password = null;
      };
      HttpConfig = {
        Address = "0.0.0.0:8011";
        OIDCConfigEndpoint = "${zitadelIssuer}/.well-known/openid-configuration";
        IdpSignKeyRefreshEnabled = true;
      };
      IdpManagerConfig = {
        ManagerType = "none";
        ExtraConfig = { };
        ClientConfig = {
          ClientID = "netbird";
          ClientSecret = "";
          GrantType = "client_credentials";
          Issuer = "";
          TokenEndpoint = "";
        };
      };
      DataStoreEncryptionKey = "ENC_PLACEHOLDER";
      StoreConfig.Engine = "sqlite";
      Datadir = "/var/lib/netbird";
      SingleAccountModeDomain = vars.domain;
      PKCEAuthorizationFlow.ProviderConfig = {
        Audience = zitadelProjectId;
        ClientID = zitadelClientId;
        Scope = "openid profile email offline_access";
        UseIDToken = true;
        RedirectURLs = [ "http://localhost:53000" ];
        ClientSecret = "";
        AuthorizationEndpoint = "";
        TokenEndpoint = "";
      };
      DeviceAuthorizationFlow.ProviderConfig = {
        Audience = zitadelProjectId;
        ClientID = zitadelClientId;
        Scope = "openid profile email offline_access";
        UseIDToken = true;
        DeviceAuthEndpoint = "";
        TokenEndpoint = null;
        Domain = null;
      };
      ReverseProxy = {
        TrustedPeers = [ "0.0.0.0/0" ];
        TrustedHTTPProxies = [ ];
        TrustedHTTPProxiesCount = 0;
      };
    }
  );
in
{
  options.my.services.netbird.server = {
    enable = lib.mkEnableOption "NetBird VPN control plane (OCI: management + signal + dashboard, native: coturn + nginx)";
  };

  config = lib.mkIf cfg.server.enable {

    # ── Secrets ───────────────────────────────────────────────────────────────
    sops.secrets = {
      "netbird/turn_password" = {
        owner = "turnserver";
        group = "turnserver";
        mode = "0440";
      };
      "netbird/encryption_key" = {
        mode = "0440";
      };
    };

    # ── coturn (native) ───────────────────────────────────────────────────────
    # Secret is injected at runtime via preStart — coturn config is read-only
    # in /nix/store, so we write the HMAC secret to a separate file in /run
    # and reference it with "include".
    systemd.tmpfiles.rules = [
      "d /var/lib/netbird-mgmt 0750 root root -"
    ];

    services.coturn = {
      enable = true;
      listening-port = 3478;
      tls-listening-port = 5349;
      cert = "/var/lib/acme/${domain}/fullchain.pem";
      pkey = "/var/lib/acme/${domain}/key.pem";
      realm = domain;
      min-port = 49152;
      max-port = 65535;
      use-auth-secret = true;
      static-auth-secret-file = config.sops.secrets."netbird/turn_password".path;
      extraConfig = ''
        fingerprint
        no-tlsv1
        no-tlsv1_1
      '';
    };

    systemd.services.coturn = {
      after = [
        "sops-install-secrets.service"
        "acme-${domain}.service"
      ];
      wants = [ "acme-${domain}.service" ];
    };

    # coturn needs read access to ACME certs — add turnserver to nginx group
    # rather than changing the cert group (which would break nginx's own access)
    users.users.turnserver.extraGroups = [ "nginx" ];

    # ── management.json generation (oneshot before container starts) ──────────
    systemd.services.netbird-management-config = {
      description = "Generate NetBird management.json with runtime secrets";
      wantedBy = [ "podman-netbird-management.service" ];
      before = [ "podman-netbird-management.service" ];
      after = [ "sops-install-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.jq ];
      script = ''
        TURN="$(cat ${config.sops.secrets."netbird/turn_password".path})"
        ENC="$(cat ${config.sops.secrets."netbird/encryption_key".path})"
        jq \
          --arg turn "$TURN" \
          --arg enc  "$ENC" \
          '.TURNConfig.Turns[0].Password = $turn
           | .TURNConfig.Secret           = $turn
           | .DataStoreEncryptionKey      = $enc' \
          ${mgmtConfigTemplate} > /var/lib/netbird-mgmt/management.json
        chmod 600 /var/lib/netbird-mgmt/management.json
      '';
    };

    # ── OCI containers ────────────────────────────────────────────────────────

    virtualisation.oci-containers.containers = {

      netbird-management = {
        image = "netbirdio/management:latest";
        ports = [ "127.0.0.1:8011:8011" ];
        volumes = [
          "/var/lib/netbird-mgmt:/var/lib/netbird"
          "/var/lib/netbird-mgmt/management.json:/etc/netbird/management.json:ro"
        ];
        cmd = [
          "--port"
          "8011"
          "--log-file"
          "console"
          "--disable-anonymous-metrics"
          "true"
          "--single-account-mode-domain"
          vars.domain
        ];
      };

      netbird-signal = {
        image = "netbirdio/signal:latest";
        ports = [ "127.0.0.1:10000:80" ];
        cmd = [
          "--log-file"
          "console"
        ];
      };

      netbird-dashboard = {
        image = "netbirdio/dashboard:latest";
        ports = [ "127.0.0.1:8080:80" ];
        environment = {
          AUTH_AUTHORITY = zitadelIssuer;
          AUTH_CLIENT_ID = zitadelClientId;
          AUTH_AUDIENCE = zitadelProjectId;
          AUTH_SUPPORTED_SCOPES = "openid profile email";
          AUTH_REDIRECT_URI = "https://${domain}/auth";
          AUTH_SILENT_REDIRECT_URI = "https://${domain}/silent-auth";
          NETBIRD_MGMT_API_ENDPOINT = "https://${domain}";
          NETBIRD_MGMT_GRPC_API_ENDPOINT = "https://${domain}";
          USE_AUTH0 = "false";
        };
      };
    };

    # management container must start after config is generated
    systemd.services.podman-netbird-management = {
      after = [ "netbird-management-config.service" ];
      requires = [ "netbird-management-config.service" ];
    };

    # ── nginx (reverse proxy + ACME) ──────────────────────────────────────────
    services.nginx.enable = true;

    services.nginx.virtualHosts.${domain} = {
      enableACME = true;
      forceSSL = true;
      http2 = true;

      locations = {
        # Dashboard SPA
        "/" = {
          proxyPass = "http://127.0.0.1:8080";
          extraConfig = ''
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };

        # Management REST API
        "/api" = {
          proxyPass = "http://127.0.0.1:8011";
          extraConfig = ''
            proxy_set_header Host              $host;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };

        # Management gRPC
        "/management.ManagementService/" = {
          extraConfig = ''
            grpc_pass       grpc://127.0.0.1:8011;
            grpc_set_header Host $host;
          '';
        };

        # Signal gRPC
        "/signalexchange.SignalExchange/" = {
          extraConfig = ''
            grpc_pass       grpc://127.0.0.1:10000;
            grpc_set_header Host $host;
          '';
        };
      };
    };
  };
}
