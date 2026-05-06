# Declarative disk layout for HP EliteDesk 705 G4 (boulder)
# Uses ZFS on a single NVMe SSD via disko
#
# Verify disk device path before installation:
#   lsblk -d -o NAME,SIZE,MODEL
#
# To install via nixos-anywhere:
#   just provision-boulder <IP>
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";
      options.ashift = "12"; # 4K sector alignment for SSDs
      rootFsOptions = {
        compression = "lz4";
        mountpoint = "none";
        xattr = "sa";
        acltype = "posixacl"; # Required for Podman rootless
        "com.sun:auto-snapshot" = "false";
      };
      postCreateHook = ''
        zfs list -t snapshot -H -o name | grep -E '^zroot/root@blank$' || zfs snapshot zroot/root@blank
      '';
      datasets = {
        # Ephemeral root — rolled back to blank on each boot (optional)
        "root" = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
        };
        # Nix store — large, persistent, never backed up
        "nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };
        # All service state — persistent, backed up
        "var" = {
          type = "zfs_fs";
          mountpoint = "/var";
          options.mountpoint = "legacy";
        };
        # User home directories
        "home" = {
          type = "zfs_fs";
          mountpoint = "/home";
          options.mountpoint = "legacy";
        };
        # Reserved space — keeps pool below 80% threshold
        "reserved" = {
          type = "zfs_fs";
          options = {
            mountpoint = "none";
            refreservation = "10G";
          };
        };
        # Container storage for Podman (ext4 on ZFS volume)
        # 100G for Jellyfin/Immich container layers and transcoding cache
        "containers" = {
          type = "zfs_volume";
          size = "100G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/lib/containers";
          };
        };
      };
    };
  };
}
