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

  # management.json template — TURN password and encryption key are injected at
  # runtime by the netbird-management-config systemd oneshot.
  #
  # EmbeddedIdP.Enabled = true activates the built-in Dex IdP (available since
  # v0.62.0 in netbirdio/management). When enabled, the binary auto-configures
  # HttpConfig (AuthIssuer, AuthAudience, AuthKeysLocation, OIDCConfigEndpoint)
  # from the Issuer value — no manual OIDC fields needed.
  #
  # IdpManagerConfig is omitted intentionally: it is only for external IdP managers
  # (Auth0, Zitadel, Keycloak). With embedded Dex it must not be present.
  mgmtConfigTemplate = pkgs.writeText "management.json.tmpl" (
    builtins.toJSON {
      Stuns = [
        {
          Proto = "udp";
          URI = "stun:${domain}:3478";
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
        TimeBasedCredentials = true;
      };
      Signal = {
        Proto = "https";
        URI = "${domain}:443";
        Username = null;
        Password = null;
      };
      HttpConfig = {
        Address = "0.0.0.0:8080";
        # Pocket ID OIDC discovery — management validates peer JWTs against this.
        OIDCConfigEndpoint = "https://pocket-id.${vars.domain}/.well-known/openid-configuration";
        # Audience must match the Client ID created in Pocket ID for NetBird.
        AuthAudience = "4c1b8f6b-736c-4f52-800b-022c45a8970f"; # gitleaks:allow — public OIDC client ID
        IdpSignKeyRefreshEnabled = true;
      };
      EmbeddedIdP = {
        # Embedded Dex disabled — Pocket ID on the VPS is the OIDC provider.
        Enabled = false;
      };
      DataStoreEncryptionKey = "ENC_PLACEHOLDER";
      StoreConfig.Engine = "sqlite";
      Datadir = "/var/lib/netbird";
      SingleAccountModeDomain = vars.domain;
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
    enable = lib.mkEnableOption "NetBird VPN control plane (OCI: management + signal + dashboard, native: coturn)";
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
      # Contains: NETBIRD_IDP_MGMT_EXTRA_API_TOKEN=<pocket-id-api-token>
      "pocket-id/netbird-env" = { };
    };

    # ── coturn (native) ───────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d /var/lib/netbird-mgmt 0750 root root -"
    ];

    services.coturn = {
      enable = true;
      listening-port = 3478;
      tls-listening-port = 5349;
      # Caddy manages ACME certs in its own data dir (HTTP-01 challenge, public VPS IP).
      # turnserver is added to the caddy group so it can read these files.
      cert = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${domain}/${domain}.crt";
      pkey = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${domain}/${domain}.key";
      realm = domain;
      min-port = 49152;
      max-port = 65535;
      use-auth-secret = true;
      static-auth-secret-file = config.sops.secrets."netbird/turn_password".path;
      extraConfig = ''
        fingerprint
        no-tlsv1
        no-tlsv1_1
        # Block SSRF: deny relay to RFC1918, loopback, link-local, and cloud metadata
        denied-peer-ip=10.0.0.0-10.255.255.255
        denied-peer-ip=172.16.0.0-172.31.255.255
        denied-peer-ip=192.168.0.0-192.168.255.255
        denied-peer-ip=127.0.0.0-127.255.255.255
        denied-peer-ip=169.254.0.0-169.254.255.255
        # Block IPv4-mapped IPv6 bypass (affects coturn < 4.9.0)
        denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
        no-multicast-peers
        no-cli
        user-quota=10
        total-quota=100
        max-bps=512000
      '';
    };

    # coturn reads ACME certs managed by Caddy — add turnserver to caddy group.
    # Caddy obtains the cert asynchronously; coturn will restart if it starts
    # before the cert file exists (Restart=on-failure is the coturn default).
    users.users.turnserver.extraGroups = [ "caddy" ];

    systemd.services.coturn = {
      after = [
        "sops-install-secrets.service"
        "caddy.service"
      ];
      wants = [ "caddy.service" ];
    };

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

      # Management REST API + gRPC — Pocket ID OIDC for auth, no embedded Dex
      # Signal is still a separate image (not merged as of v0.68.x)
      netbird-management = {
        image = "netbirdio/management:0.68.3";
        ports = [ "127.0.0.1:8080:8080" ];
        volumes = [
          "/var/lib/netbird-mgmt:/var/lib/netbird"
          "/var/lib/netbird-mgmt/management.json:/etc/netbird/management.json:ro"
        ];
        environment = {
          # User management: Pocket ID API (list/sync users in NetBird dashboard)
          NETBIRD_MGMT_IDP = "pocketid";
          NETBIRD_IDP_MGMT_EXTRA_MANAGEMENT_ENDPOINT = "https://pocket-id.${vars.domain}";
        };
        # Contains: NETBIRD_IDP_MGMT_EXTRA_API_TOKEN=<pocket-id-api-token>
        environmentFiles = [ config.sops.secrets."pocket-id/netbird-env".path ];
        # Container DNS cannot resolve external hostnames for same-host services.
        # Pin pocket-id.grab-lab.gg directly to the VPS public IP so OIDC discovery
        # and user sync reach Caddy without a DNS roundtrip.
        extraOptions = [ "--add-host=pocket-id.${vars.domain}:${vars.vpsIP}" ];
        cmd = [
          "--port"
          "8080"
          "--log-file"
          "console"
          "--disable-anonymous-metrics"
          "true"
          "--single-account-mode-domain"
          vars.domain
        ];
      };

      # Signal — peer-to-peer coordination (still a separate image in v0.68.x)
      netbird-signal = {
        image = "netbirdio/signal:0.68.3";
        # Signal binary listens on port 80 inside the container by default.
        ports = [ "127.0.0.1:10000:80" ];
      };

      # React dashboard SPA
      netbird-dashboard = {
        image = "netbirdio/dashboard:v2.36.0";
        ports = [ "127.0.0.1:3000:80" ];
        environment = {
          # Pocket ID OIDC — passkey-only IdP on the VPS
          AUTH_AUTHORITY = "https://pocket-id.${vars.domain}";
          AUTH_CLIENT_ID = "4c1b8f6b-736c-4f52-800b-022c45a8970f"; # gitleaks:allow — public OIDC client ID
          AUTH_AUDIENCE = "4c1b8f6b-736c-4f52-800b-022c45a8970f"; # gitleaks:allow — public OIDC client ID
          # offline_access not supported by Pocket ID — omit it
          AUTH_SUPPORTED_SCOPES = "openid profile email groups";
          # Relative paths required — dashboard prepends window.location.origin.
          # Full URLs cause doubling: "https://domain" + "https://domain/nb-auth".
          AUTH_REDIRECT_URI = "/nb-auth";
          AUTH_SILENT_REDIRECT_URI = "/nb-silent-auth";
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
  };
}
