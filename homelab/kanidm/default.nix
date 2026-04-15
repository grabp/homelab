{ config, lib, pkgs, vars, ... }:

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
        Type            = "oneshot";
        RemainAfterExit = true;
      };
      path   = [ pkgs.openssl ];
      script = ''
        install -d -m 750 -o kanidm -g kanidm /var/lib/kanidm
        if [ ! -f /var/lib/kanidm/tls.pem ]; then
          openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
            -keyout /var/lib/kanidm/tls.key \
            -out    /var/lib/kanidm/tls.pem \
            -days 3650 -nodes \
            -subj '/CN=id.${vars.domain}'
          chown kanidm:kanidm /var/lib/kanidm/tls.key /var/lib/kanidm/tls.pem
          chmod 600 /var/lib/kanidm/tls.key
          chmod 644 /var/lib/kanidm/tls.pem
        fi
      '';
    };

    # Hard-order: kanidm cannot start until the cert is present.
    systemd.services.kanidm = {
      requires = [ "kanidm-tls-cert.service" ];
      after    = [ "kanidm-tls-cert.service" ];
    };

    # -------------------------------------------------------------------------
    # Kanidm server
    # -------------------------------------------------------------------------
    services.kanidm = {
      enableServer = true;
      # nixos-25.11 module defaults to kanidm_1_4 which is EOL and removed.
      # Pin to 1.9; withSecretProvisioning includes the kanidm-provision helper.
      package = pkgs.kanidmWithSecretProvisioning_1_9;
      serverSettings = {
        origin          = "https://id.${vars.domain}";
        domain          = "id.${vars.domain}";
        bindaddress     = "127.0.0.1:8443";
        ldapbindaddress = "127.0.0.1:636";
        tls_chain       = "/var/lib/kanidm/tls.pem";
        tls_key         = "/var/lib/kanidm/tls.key";
      };

      provision = {
        enable             = true;
        # Connect to Kanidm directly (not via Caddy) so provisioning works even
        # if Caddy isn't yet fully ready. acceptInvalidCerts allows the self-signed cert.
        instanceUrl        = "https://127.0.0.1:8443";
        acceptInvalidCerts = true;
        adminPasswordFile    = config.sops.secrets."kanidm/admin_password".path;
        idmAdminPasswordFile = config.sops.secrets."kanidm/idm_admin_password".path;

        persons."admin" = {
          displayName   = "Admin";
          mailAddresses = [ "admin@${vars.domain}" ];
        };

        groups."homelab_users".members  = [ "admin" ];
        groups."homelab_admins".members = [ "admin" ];

        # --- Grafana OAuth2 client -------------------------------------------
        # Co-located here per STRUCTURE.md convention (auth config lives alongside
        # the IdP config, not centralised in kanidm/default.nix for the service).
        # basicSecretFile lets us pre-generate the secret in sops and share it with
        # Grafana's config, avoiding a two-phase deploy.
        systems.oauth2."grafana" = {
          displayName     = "Grafana";
          originUrl       = "https://grafana.${vars.domain}/login/generic_oauth";
          originLanding   = "https://grafana.${vars.domain}";
          basicSecretFile = config.sops.secrets."kanidm/grafana_client_secret".path;
          scopeMaps."homelab_users" = [ "openid" "profile" "email" "groups" ];
        };
      };
    };

    # -------------------------------------------------------------------------
    # Secrets
    # -------------------------------------------------------------------------
    sops.secrets."kanidm/admin_password"     = {};
    sops.secrets."kanidm/idm_admin_password" = {};

    # mode 0444: world-readable so both the kanidm provisioning process and the
    # grafana service (which reads it via $__file{...}) can access it.
    # This is an internal OAuth2 client secret — not a user credential.
    sops.secrets."kanidm/grafana_client_secret" = { mode = "0444"; };

    # -------------------------------------------------------------------------
    # Firewall
    # Port 8443 (Kanidm HTTPS) is NOT opened — Caddy proxies via localhost only.
    # Port 636 (LDAPS) opened now for future Jellyfin LDAP integration (Stage 15).
    # -------------------------------------------------------------------------
    networking.firewall.allowedTCPPorts = [ 636 ];
  };
}
