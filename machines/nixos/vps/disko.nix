# Declarative disk layout for Hetzner CX22 VPS
# Uses simple ext4 — no ZFS needed on a VPS.
#
# Hetzner Cloud CX-series VMs use SeaBIOS (legacy BIOS), not UEFI.
# GPT + BIOS requires a 1M EF02 "BIOS boot" partition for GRUB to embed its
# second-stage bootloader. No ESP/vfat partition needed in BIOS mode.
#
# ⚠ VERIFY disk device: Hetzner CX22 uses /dev/sda. Confirm with lsblk.
{
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # BIOS boot partition: GRUB embeds stage 2 here when booting GPT+BIOS.
        # Not mounted, no filesystem — GRUB writes directly to the raw partition.
        bios = {
          type = "EF02";
          size = "1M";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
