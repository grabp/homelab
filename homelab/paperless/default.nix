# homelab/paperless/default.nix — Paperless-ngx document management
#
# Native NixOS module, PostgreSQL via Unix socket (peer auth, no password).
# Documents stored on local ZFS (/var/lib/paperless) — already covered by
# boulder's restic backup (default paths include /var/lib).
#
# Proxied by Caddy on pebble: https://paperless.grab-lab.gg → boulderIP:8010
#
# PRE-DEPLOY:
#   just edit-secrets-boulder → add: paperless/admin_password: "<password>"
{
  config,
  lib,
  vars,
  ...
}:

let
  cfg = config.my.services.paperless;
in
{
  options.my.services.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx document management";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8010;
      description = "Paperless-ngx web port (referenced by Caddy on pebble).";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Sops secret: Paperless web UI admin password ───────────────────────────
    # Used only on first run to create the 'admin' superuser.
    # Format: single line containing the password (no key=value).
    sops.secrets."paperless/admin_password" = {
      owner = config.services.paperless.user;
      mode = "0400";
    };

    # ── Paperless-ngx native service ──────────────────────────────────────────
    # database.createLocally is intentionally left false (default): Stage 12
    # already created the 'paperless' database and user in the shared PostgreSQL
    # instance. Setting it false also ensures PrivateNetwork = false for all
    # paperless systemd units, which is required for the web server to bind to
    # 0.0.0.0 and for the workers to access the PostgreSQL Unix socket.
    #
    # mediaDir and consumptionDir use module defaults (/var/lib/paperless/{media,consume}).
    # This avoids NFS permission issues: Synology Windows ACLs override Unix mode
    # bits and deny unknown UIDs even on 777 directories.
    services.paperless = {
      enable = true;
      address = "0.0.0.0"; # LAN-accessible; firewall below restricts to eth0
      port = cfg.port;
      passwordFile = config.sops.secrets."paperless/admin_password".path;
      settings = {
        PAPERLESS_DBENGINE = "postgresql";
        PAPERLESS_DBHOST = "/run/postgresql"; # Unix socket — peer auth, no password
        PAPERLESS_DBNAME = "paperless";
        PAPERLESS_DBUSER = "paperless"; # matches the systemd service user
        PAPERLESS_URL = "https://paperless.${vars.domain}";
        PAPERLESS_OCR_LANGUAGE = "pol+eng";
        # Some PDFs trigger a Ghostscript soft error during PDF/A conversion
        # (-dPDFSTOPONERROR). This setting makes ocrmypdf continue instead of
        # failing the entire document — OCR still runs, the output is not PDF/A
        # strict but is otherwise complete.
        PAPERLESS_OCR_USER_ARGS = builtins.toJSON {
          continue_on_soft_render_error = true;
          optimize = 0; # disable JPEG transcoding — avoids transcode_jpegs failures on complex PDFs
        };
      };
    };

    # paperless-web must start after PostgreSQL is ready
    systemd.services.paperless-web = {
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
    };

    # ── Firewall: LAN (eth0) access for Caddy on pebble ───────────────────────
    networking.firewall.interfaces."eth0".allowedTCPPorts = [ cfg.port ];
  };
}
