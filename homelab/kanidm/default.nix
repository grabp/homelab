{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

let
  cfg = config.my.services.kanidm;
in
{
  options.my.services.kanidm.enable = lib.mkEnableOption "Kanidm OIDC + LDAP identity provider";

  config = lib.mkIf cfg.enable {

    # -------------------------------------------------------------------------
    # Self-signed TLS cert for Kanidm's internal HTTPS binding.
    # Caddy proxies id.grab-lab.gg → 127.0.0.1:8443 with tls_insecure_skip_verify,
    # so the cert contents don't matter — Kanidm requires TLS even on localhost.
    # The oneshot generates the cert once and skips if it already exists.
    # -------------------------------------------------------------------------
    systemd.services.kanidm-tls-cert = {
      description = "Generate Kanidm self-signed TLS certificate";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.openssl ];
      script = ''
        install -d -m 750 -o kanidm -g kanidm /var/lib/kanidm
        # Regenerate if missing or if the cert has CA:TRUE (the old bad default).
        # kanidm 1.9 strict TLS rejects CA:TRUE certs with CaUsedAsEndEntity.
        needs_regen=0
        [ ! -f /var/lib/kanidm/tls.pem ] && needs_regen=1
        if [ -f /var/lib/kanidm/tls.pem ]; then
          openssl x509 -in /var/lib/kanidm/tls.pem -noout -text 2>/dev/null \
            | grep -q "CA:TRUE" && needs_regen=1
        fi
        if [ "$needs_regen" = "1" ]; then
          openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
            -keyout /var/lib/kanidm/tls.key \
            -out    /var/lib/kanidm/tls.pem \
            -days 3650 -nodes \
            -subj '/CN=id.${vars.domain}' \
            -addext "basicConstraints=CA:FALSE" \
            -addext "subjectAltName=IP:127.0.0.1,DNS:id.${vars.domain}"
          chown kanidm:kanidm /var/lib/kanidm/tls.key /var/lib/kanidm/tls.pem
          chmod 600 /var/lib/kanidm/tls.key
          chmod 644 /var/lib/kanidm/tls.pem
        fi
      '';
    };

    # Hard-order: kanidm cannot start until the cert is present.
    systemd.services.kanidm = {
      requires = [ "kanidm-tls-cert.service" ];
      after = [ "kanidm-tls-cert.service" ];
    };

    # -------------------------------------------------------------------------
    # Kanidm server
    # -------------------------------------------------------------------------
    # kanidm CLI available system-wide without enableClient (which requires clientSettings).
    environment.systemPackages = [ pkgs.kanidmWithSecretProvisioning_1_9 ];

    services.kanidm = {
      enableServer = true;
      # nixos-25.11 module defaults to kanidm_1_4 which is EOL and removed.
      # Pin to 1.9; withSecretProvisioning includes the kanidm-provision helper.
      package = pkgs.kanidmWithSecretProvisioning_1_9;
      serverSettings = {
        origin = "https://id.${vars.domain}";
        domain = "id.${vars.domain}";
        bindaddress = "127.0.0.1:8443";
        ldapbindaddress = "127.0.0.1:636";
        tls_chain = "/var/lib/kanidm/tls.pem";
        tls_key = "/var/lib/kanidm/tls.key";
      };

      provision = {
        enable = true;
        # Connect to Kanidm directly (not via Caddy) so provisioning works even
        # if Caddy isn't yet fully ready. acceptInvalidCerts allows the self-signed cert.
        instanceUrl = "https://127.0.0.1:8443";
        acceptInvalidCerts = true;
        adminPasswordFile = config.sops.secrets."kanidm/admin_password".path;
        idmAdminPasswordFile = config.sops.secrets."kanidm/idm_admin_password".path;

        # NOTE: "admin" is Kanidm's built-in system recovery account — cannot be
        # used as a person name (409 conflict). Use a distinct personal username.
        persons."grabowskip" = {
          displayName = "Patryk Grabowski";
          mailAddresses = [ "admin@${vars.domain}" ];
        };

        groups."homelab_users".members = [ "grabowskip" ];
        groups."homelab_admins".members = [ "grabowskip" ];

        # --- Homepage OAuth2 client ------------------------------------------
        # oauth2-proxy sits in front of Homepage and handles the PKCE dance.
        # Redirect URI matches oauth2-proxy's default /oauth2/callback path.
        systems.oauth2."homepage" = {
          displayName = "Homepage";
          originUrl    = "https://home.${vars.domain}/oauth2/callback";
          originLanding = "https://home.${vars.domain}";
          basicSecretFile = config.sops.secrets."kanidm/homepage_client_secret".path;
          scopeMaps."homelab_users" = [ "openid" "profile" "email" ];
        };

        # --- Grafana OAuth2 client -------------------------------------------
        # Co-located here per STRUCTURE.md convention (auth config lives alongside
        # the IdP config, not centralised in kanidm/default.nix for the service).
        # basicSecretFile lets us pre-generate the secret in sops and share it with
        # Grafana's config, avoiding a two-phase deploy.
        systems.oauth2."grafana" = {
          displayName = "Grafana";
          originUrl = "https://grafana.${vars.domain}/login/generic_oauth";
          originLanding = "https://grafana.${vars.domain}";
          basicSecretFile = config.sops.secrets."kanidm/grafana_client_secret".path;
          scopeMaps."homelab_users" = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
        };
      };
    };

    # -------------------------------------------------------------------------
    # Secrets
    # -------------------------------------------------------------------------
    # owner = "kanidm": the provisioning post-start script runs as the kanidm
    # user and reads these files directly. Default root:root 0400 → permission denied.
    sops.secrets."kanidm/admin_password" = {
      owner = "kanidm";
    };
    sops.secrets."kanidm/idm_admin_password" = {
      owner = "kanidm";
    };

    # owner=kanidm: provisioning reads it to set the Grafana OAuth2 client credential.
    # group=grafana: Grafana service reads it via $__file{...} at runtime.
    # mode=0440: owner+group readable only — no world-read.
    sops.secrets."kanidm/grafana_client_secret" = {
      owner = "kanidm";
      group = "grafana";
      mode  = "0440";
    };

    # Homepage client secret — kanidm provisioning reads it to set the OAuth2
    # client credential. oauth2-proxy reads its copy from oauth2-proxy/homepage_env
    # (a separate sops secret) so this stays owner=kanidm, 0400.
    sops.secrets."kanidm/homepage_client_secret" = {
      owner = "kanidm";
    };

    # -------------------------------------------------------------------------
    # Firewall
    # Port 8443 (Kanidm HTTPS) is NOT opened — Caddy proxies via localhost only.
    # Port 636 (LDAPS) opened now for future Jellyfin LDAP integration (Stage 15).
    # -------------------------------------------------------------------------
    networking.firewall.allowedTCPPorts = [ 636 ];
  };
}
