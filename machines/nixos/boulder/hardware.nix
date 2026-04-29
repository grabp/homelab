# Hardware configuration for HP EliteDesk 705 G4 SFF (boulder)
# AMD Ryzen 5 PRO 2400G (Vega 11 iGPU), 32 GB DDR4, 250 GB SATA SSD
#
# Regenerate after first boot with:
#   nixos-generate-config --show-hardware-config
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
