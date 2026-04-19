{ config, lib, ... }:

let
  cfg = config.my.services.backup;
  nasIP = "192.168.10.100";
  nasExport = "/volume1/zfs-backups"; # Synology volume 1, shared folder "zfs-backups"
  mountPoint = "/mnt/nas/backup";
in
{
  options.my.services.backup.enable = lib.mkEnableOption "Sanoid snapshots + Restic NFS backup";

  config = lib.mkIf cfg.enable {

    # ── NFS mount — Synology NAS ─────────────────────────────────────────────
    # NFSv4, automounted on demand, unmounted after 10 min idle.
    # Synology NFS permission: pebble IP (192.168.10.50), squash = No mapping.
    # _netdev: mount after network is up; nofail: don't block boot if NAS is unreachable.
    fileSystems."${mountPoint}" = {
      device = "${nasIP}:${nasExport}";
      fsType = "nfs";
      options = [
        "nfsvers=4"
        "nofail" # don't block boot if NAS is down
        "_netdev" # mount after network-online.target
        "x-systemd.automount" # mount on first access, not at boot
        "x-systemd.idle-timeout=600" # unmount after 10 min idle
        "x-systemd.mount-timeout=30" # fail fast if NAS unreachable at access time
      ];
    };

    # ── ZFS snapshots — Sanoid ───────────────────────────────────────────────
    # Local ZFS snapshots on pebble. No NAS involvement — runs regardless of NAS state.
    # Datasets: zroot/var (all service state), zroot/home (admin home dir).
    services.sanoid = {
      enable = true;
      templates.homelab = {
        hourly = 24; # keep 24 hourly snapshots
        daily = 7; # keep 7 daily snapshots
        weekly = 4; # keep 4 weekly snapshots
        monthly = 3; # keep 3 monthly snapshots
        autosnap = true;
        autoprune = true;
      };
      datasets = {
        "zroot/var" = {
          useTemplate = [ "homelab" ];
        };
        "zroot/home" = {
          useTemplate = [ "homelab" ];
        };
      };
    };

    # ── Restic: Vaultwarden daily backups → NAS (NFS) ────────────────────────
    # Backs up /var/backup/vaultwarden (daily SQLite dumps via services.vaultwarden.backupDir).
    # Repository: local path on the NFS mount — simplest restic backend, no auth needed.
    # Pre-deploy: just edit-secrets → add: restic/password: "your-strong-password"
    sops.secrets."restic/password" = { };

    services.restic.backups.vaultwarden = {
      initialize = true; # create repo on first run if it doesn't exist
      passwordFile = config.sops.secrets."restic/password".path;
      repository = "${mountPoint}/restic/vaultwarden";
      paths = [ "/var/backup/vaultwarden" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true; # run immediately if last scheduled run was missed
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 3"
      ];
    };

    # Ensure restic runs after the NFS automount unit is active.
    systemd.services."restic-backups-vaultwarden" = {
      after = [ "mnt-nas-backup.automount" ];
      requires = [ "mnt-nas-backup.automount" ];
    };
  };
}
