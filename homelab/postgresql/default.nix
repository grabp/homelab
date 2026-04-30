{
  config,
  lib,
  ...
}:

let
  cfg = config.my.services.postgresql;
in
{
  options.my.services.postgresql = {
    enable = lib.mkEnableOption "Shared PostgreSQL instance";
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;

      # paperless OCI container connects via mounted Unix socket.
      # trust auth bypasses peer UID check — paperless-ngx container runs as UID 1000,
      # not the host 'paperless' user (UID 315). Placed before the default peer catch-all.
      authentication = lib.mkAfter ''
        local paperless paperless trust
      '';

      # Databases for boulder services (Stages 13, 14, 16)
      ensureDatabases = [
        "outline"
        "vikunja"
        "paperless"
      ];

      ensureUsers = [
        {
          name = "outline";
          ensureDBOwnership = true;
        }
        {
          name = "vikunja";
          ensureDBOwnership = true;
        }
        {
          name = "paperless";
          ensureDBOwnership = true;
        }
      ];
    };

    # Daily logical dumps — boulder restic job will pick up this path
    services.postgresqlBackup = {
      enable = true;
      databases = [
        "outline"
        "vikunja"
        "paperless"
      ];
      compression = "zstd";
      location = "/var/backup/postgresql";
      startAt = "daily";
    };
  };
}
