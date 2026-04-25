---
kind: pattern
number: 3
tags: [disko, zfs, ephemeral]
---

# Pattern 3: disko single-disk ZFS with ephemeral root

```nix
# machines/nixos/pebble/disko.nix
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/sda";  # ⚠ VERIFY: check actual device path
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
            content = { type = "zfs"; pool = "zroot"; };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        compression = "lz4";
        mountpoint = "none";
        xattr = "sa";
        acltype = "posixacl";
        "com.sun:auto-snapshot" = "false";
      };
      postCreateHook = ''
        zfs list -t snapshot -H -o name | grep -E '^zroot/root@blank$' || zfs snapshot zroot/root@blank
      '';
       datasets = {
        "root" = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
        };
        "nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };
        "var" = {
          type = "zfs_fs";
          mountpoint = "/var";
          options.mountpoint = "legacy";
        };
        "home" = {
          type = "zfs_fs";
          mountpoint = "/home";
          options.mountpoint = "legacy";
        };
        "containers" = {
          type = "zfs_volume";
          size = "50G";
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
```

**Source:** Based on disko/example/zfs.nix and notthebee's aria disko.nix. The `postCreateHook` creates a blank snapshot for ephemeral root rollback ✅.

**Ephemeral root rollback service** (optional, add to machine config):
```nix
boot.initrd.systemd = {
  enable = true;
  services.rollback-root = {
    after = [ "zfs-import-zroot.service" ];
    wantedBy = [ "initrd.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs rollback -r zroot/root@blank
    '';
  };
};
```
