{
  config,
  lib,
  vars,
  ...
}:

let
  cfg = config.my.services.vaultwarden;
in
{
  options.my.services.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden password manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8222;
      description = "Port for Vaultwarden web interface";
    };
  };

  config = lib.mkIf cfg.enable {
    # vaultwarden/admin_token must contain: ADMIN_TOKEN=<generate-with-openssl-rand-base64-48>
    # Add with: just edit-secrets
    sops.secrets."vaultwarden/admin_token" = {
      owner = "vaultwarden";
      restartUnits = [ "vaultwarden.service" ];
    };

    services.vaultwarden = {
      enable = true;
      backupDir = "/var/backup/vaultwarden";
      environmentFile = config.sops.secrets."vaultwarden/admin_token".path;
      config = {
        DOMAIN = "https://vault.${vars.domain}";
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = cfg.port;
        SIGNUPS_ALLOWED = false; # Re-enable temporarily if you need to add another account
        INVITATIONS_ALLOWED = true;
        SHOW_PASSWORD_HINT = false;
      };
    };

    # Daily backup timer is built-in via backupDir
    # Backups stored in /var/backup/vaultwarden/

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
