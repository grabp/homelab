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
