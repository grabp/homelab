{ config, lib, ... }:

let
  cfg = config.my.services.backup;

  # ── NAS connection details ────────────────────────────────────────────────
  # PLACEHOLDER: fill in before first deploy, then run:
  #   sudo ssh-keygen -t ed25519 -f /root/.ssh/syncoid_ed25519 -N "" -C "syncoid@pebble"
  #   sudo cat /root/.ssh/syncoid_ed25519.pub  # add to NAS authorized_keys
  nasUser = "admin";          # NAS SSH username
  nasIP   = "192.168.10.X";  # NAS IP address
  nasPool = "tank";           # NAS ZFS pool name (syncoid) or base path (restic)
in
{
  options.my.services.backup.enable =
    lib.mkEnableOption "Sanoid snapshots + Syncoid NAS replication + Restic";

  config = lib.mkIf cfg.enable {

    # ── ZFS snapshots — Sanoid ───────────────────────────────────────────────
    # Runs on pebble only (ZFS is required). Snapshots are local; syncoid replicates them.
    services.sanoid = {
      enable = true;
      templates.homelab = {
        hourly  = 24;   # keep 24 hourly snapshots
        daily   = 7;    # keep 7 daily snapshots
        weekly  = 4;    # keep 4 weekly snapshots
        monthly = 3;    # keep 3 monthly snapshots
        autosnap  = true;
        autoprune = true;
      };
      datasets = {
        "zroot/var"  = { useTemplate = [ "homelab" ]; };  # all service state
        "zroot/home" = { useTemplate = [ "homelab" ]; };  # admin home dir
      };
    };

    # ── ZFS replication to NAS — Syncoid ─────────────────────────────────────
    # Runs hourly (default). Sends incremental snapshots created by sanoid to the NAS.
    # Pre-deploy: generate /root/.ssh/syncoid_ed25519 and add pubkey to NAS authorized_keys.
    # NAS must have destination datasets: ${nasPool}/pebble/var, ${nasPool}/pebble/home
    services.syncoid = {
      enable = true;
      sshKey = "/root/.ssh/syncoid_ed25519";
      commands = {
        "var-to-nas" = {
          source = "zroot/var";
          target = "${nasUser}@${nasIP}:${nasPool}/pebble/var";
        };
        "home-to-nas" = {
          source = "zroot/home";
          target = "${nasUser}@${nasIP}:${nasPool}/pebble/home";
        };
      };
    };

    # ── Restic: Vaultwarden daily SQLite backups → NAS SFTP ──────────────────
    # Backs up /var/backup/vaultwarden (daily SQLite dumps from services.vaultwarden.backupDir).
    # ZFS snapshots cover the raw database; restic provides file-level point-in-time restores.
    # Pre-deploy: add "restic/password: <password>" to secrets via: just edit-secrets
    # NAS must have: /${nasPool}/backups/restic/vaultwarden/ writable by ${nasUser}
    sops.secrets."restic/password" = {};

    services.restic.backups.vaultwarden = {
      initialize  = true;    # create repo on first run if it doesn't exist
      passwordFile = config.sops.secrets."restic/password".path;
      repository  = "sftp:${nasUser}@${nasIP}:/${nasPool}/backups/restic/vaultwarden";
      paths       = [ "/var/backup/vaultwarden" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;   # run immediately if last run was missed (e.g. pebble was off)
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 3"
      ];
    };
  };
}
