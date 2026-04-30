# homelab/paperless/default.nix — Paperless-ngx document management (OCI)
#
# Two OCI containers on a shared Podman network (paperless-net):
#   - paperless-redis: Redis broker for the Celery task queue
#   - paperless:       Paperless-ngx web + workers
#
# PostgreSQL via Unix socket mount (trust auth, no password).
# Documents stored on local ZFS (/var/lib/paperless) — covered by boulder restic.
#
# Proxied by Caddy on pebble: https://paperless.grab-lab.gg → boulderIP:8010
#
# PRE-DEPLOY:
#   just edit-secrets-boulder → set paperless/admin_password to:
#     PAPERLESS_ADMIN_PASSWORD: "<password>"   (env-file format, not plain password)
#   On boulder: sudo chown -R 1000:1000 /var/lib/paperless  (UID 315→1000 migration)
{
  config,
  lib,
  pkgs,
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
      description = "Paperless-ngx host port (Caddy on pebble proxies here).";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Sops secret: admin password as env file ───────────────────────────────
    # Format: PAPERLESS_ADMIN_PASSWORD=<password>  (env-file key=value, not plain)
    # Used only on first run to create the 'admin' superuser.
    sops.secrets."paperless/admin_password" = {
      mode = "0400"; # read by podman (root) via --env-file before container start
    };

    # ── Storage directories owned by container UID 1000 ───────────────────────
    systemd.tmpfiles.rules = [
      "d /var/lib/paperless         0750 1000 1000 -"
      "d /var/lib/paperless/media   0750 1000 1000 -"
      "d /var/lib/paperless/consume 0750 1000 1000 -"
      "d /var/lib/paperless/data    0750 1000 1000 -"
      "d /var/lib/paperless-redis   0750 999  999  -"
    ];

    # ── Shared Podman network for inter-container communication ───────────────
    # ExecStart/ExecStop must use writeShellScript — systemd does not interpret
    # shell operators (||, redirects) in bare ExecStart strings.
    systemd.services.podman-paperless-network = {
      wantedBy = [ "multi-user.target" ];
      before = [
        "podman-paperless.service"
        "podman-paperless-redis.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "paperless-network-up" ''
          ${pkgs.podman}/bin/podman network create paperless-net || true
        '';
        ExecStop = pkgs.writeShellScript "paperless-network-down" ''
          ${pkgs.podman}/bin/podman network rm -f paperless-net || true
        '';
      };
    };

    # ── Redis broker — required by Celery task queue ──────────────────────────
    virtualisation.oci-containers.containers.paperless-redis = {
      image = "docker.io/library/redis:7-alpine@sha256:84b07a33a16c4584d2933128ffb28b66ee4d3284ac9dc327a5170782d5cf5b27";
      extraOptions = [
        "--network=paperless-net"
        "--name=paperless-redis"
      ];
      volumes = [ "/var/lib/paperless-redis:/data" ];
    };

    # ── Paperless-ngx ─────────────────────────────────────────────────────────
    # Internal port is 8000 (gunicorn, not configurable via env).
    # PostgreSQL: Unix socket mounted from host; trust auth in pg_hba allows
    # container UID 1000 to authenticate as 'paperless' without a password.
    virtualisation.oci-containers.containers.paperless = {
      image = "ghcr.io/paperless-ngx/paperless-ngx:2.20.15@sha256:835974fc3368fc6714aa38542db7a1f0f542d03244e39b981e519aefc100f355";
      ports = [ "0.0.0.0:${toString cfg.port}:8000" ];
      extraOptions = [ "--network=paperless-net" ];
      volumes = [
        "/run/postgresql:/run/postgresql"
        "/var/lib/paperless/media:/usr/src/paperless/media"
        "/var/lib/paperless/consume:/usr/src/paperless/consume"
        "/var/lib/paperless/data:/usr/src/paperless/data"
      ];
      environmentFiles = [ config.sops.secrets."paperless/admin_password".path ];
      environment = {
        PAPERLESS_DBENGINE = "postgresql";
        PAPERLESS_DBHOST = "/run/postgresql"; # Unix socket peer — trust auth, no password
        PAPERLESS_DBNAME = "paperless";
        PAPERLESS_DBUSER = "paperless";
        PAPERLESS_REDIS = "redis://paperless-redis:6379";
        PAPERLESS_URL = "https://paperless.${vars.domain}";
        PAPERLESS_OCR_LANGUAGE = "pol+eng";
        PAPERLESS_OCR_LANGUAGES = "pol"; # install Polish Tesseract data at container startup
        # Some PDFs trigger a Ghostscript soft error during PDF/A conversion.
        # continue_on_soft_render_error: OCR still runs, output is not strict PDF/A.
        # optimize 0: disables JPEG transcoding — avoids transcode_jpegs failures.
        PAPERLESS_OCR_USER_ARGS = builtins.toJSON {
          continue_on_soft_render_error = true;
          optimize = 0;
        };
      };
    };

    # Pattern 19: NixOS firewall reload flushes Netavark DNAT rules — restart
    # containers so port mappings are re-registered.
    systemd.services.podman-paperless = {
      after = [
        "firewall.service"
        "postgresql.service"
        "podman-paperless-network.service"
      ];
      requires = [
        "postgresql.service"
        "podman-paperless-network.service"
      ];
      partOf = [ "firewall.service" ];
    };
    systemd.services.podman-paperless-redis = {
      after = [
        "firewall.service"
        "podman-paperless-network.service"
      ];
      requires = [ "podman-paperless-network.service" ];
      partOf = [ "firewall.service" ];
    };

    # ── Firewall: LAN (eth0) access for Caddy on pebble ───────────────────────
    networking.firewall.interfaces."eth0".allowedTCPPorts = [ cfg.port ];
  };
}
