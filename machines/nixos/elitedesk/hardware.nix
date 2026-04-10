# Hardware configuration for HP Elitedesk 705 G4
# AMD Ryzen, 16GB RAM, single SSD
#
# ⚠ This is a placeholder. Replace with the actual output from:
#   nixos-generate-config --show-hardware-config
# Run on the target machine during NixOS installation (after disko partitioning).
#
# The generated config will include:
#   - boot.initrd.availableKernelModules
#   - boot.kernelModules
#   - hardware.cpu.amd.updateMicrocode
#   - Any hardware-specific settings
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Placeholder — replace with nixos-generate-config output
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # AMD CPU microcode updates
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
