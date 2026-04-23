{ config, lib, vars, ... }:

let
  cfg = config.my.services.backup;
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
      device = "${vars.nasIP}:${nasExport}";
      fsType = "nfs";
      options = [
        "nfsvers=4.1" # NFSv4.1 — max supported by Synology DSM
        "hard" # retry NFS ops indefinitely (don't return EIO)
        "noatime" # reduce write overhead
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
        daily = 30; # keep 30 daily snapshots
        monthly = 6; # keep 6 monthly snapshots
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

    # ── Restic: homelab daily backups → NAS (NFS) ────────────────────────────
    # Backs up all service state (/var/lib) and Vaultwarden SQLite dumps (/var/backup/vaultwarden).
    # Repository: local path on the NFS mount — simplest restic backend, no auth needed.
    # Pre-deploy: just edit-secrets → add: restic/password: "your-strong-password"
    sops.secrets."restic/password" = { };

    services.restic.backups.homelab = {
      initialize = true; # create repo on first run if it doesn't exist
      passwordFile = config.sops.secrets."restic/password".path;
      repository = "${mountPoint}/restic/homelab";
      paths = [
        "/var/lib"
        "/var/backup/vaultwarden"
      ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true; # run immediately if last scheduled run was missed
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];
    };

    # Ensure restic runs after the NFS automount unit is active.
    systemd.services."restic-backups-homelab" = {
      after = [ "mnt-nas-backup.automount" ];
      requires = [ "mnt-nas-backup.automount" ];
    };
  };
}
