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
        # OIDCConfigEndpoint is auto-set to Issuer + "/.well-known/openid-configuration"
        # when EmbeddedIdP is enabled. Listed here for documentation only.
        # Effective value: "https://${domain}/oauth2/.well-known/openid-configuration"
        IdpSignKeyRefreshEnabled = true;
      };
      EmbeddedIdP = {
        # Activates Dex IdP built into the management binary (since v0.62.0).
        # Issuer must match the public URL Caddy exposes for /oauth2/*.
        Enabled = true;
        Issuer = "https://${domain}/oauth2";
        # Dex auto-registers the management reverse-proxy callback
        # (https://<domain>/api/reverse-proxy/callback). These extra URIs are
        # needed for the dashboard's PKCE flow and silent token renewal.
        DashboardRedirectURIs = [
          "https://${domain}/nb-auth"
          "https://${domain}/nb-silent-auth"
        ];
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

      # Management REST API + gRPC + embedded Dex IdP
      # Signal is still a separate image (not merged as of v0.68.x)
      netbird-management = {
        image = "netbirdio/management:0.68.3";
        ports = [ "127.0.0.1:8080:8080" ];
        volumes = [
          "/var/lib/netbird-mgmt:/var/lib/netbird"
          "/var/lib/netbird-mgmt/management.json:/etc/netbird/management.json:ro"
        ];
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
          # Embedded Dex IdP — served by the management container at /oauth2
          AUTH_AUTHORITY = "https://${domain}/oauth2";
          AUTH_CLIENT_ID = "netbird-dashboard";
          AUTH_AUDIENCE = "netbird-dashboard";
          AUTH_SUPPORTED_SCOPES = "openid profile email offline_access groups";
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
