{ lib, vars, ... }: {
  imports = [
    ./disko.nix
    ./netbird-server.nix
    ../../../modules/podman
  ];

  networking.hostName = "vps";

  # GRUB bootloader for Hetzner Cloud (SeaBIOS/legacy BIOS mode).
  # GPT + BIOS requires the EF02 partition in disko.nix where GRUB embeds stage 2.
  # "nodev" = don't run grub-install (bootloader already installed by nixos-anywhere).
  # This avoids grub-install failures via deploy-rs SSH.
  boot.loader.grub = {
    enable = true;
    device = "nodev";
  };

  # Hetzner Cloud VMs use QEMU/KVM with virtio drivers.
  # These modules must be in initrd to find the root partition at boot.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];

  # sops-nix: VPS decrypts secrets using its own SSH host key.
  # The VPS age key is derived from the SSH host key during pre-provisioning
  # (see: just gen-vps-hostkey) and must be added to .sops.yaml before
  # secrets/vps.yaml is created.
  sops = {
    defaultSopsFile = ../../../secrets/vps.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  networking.firewall.enable = true;
  # nginx for ACME HTTP-01 challenge and NetBird dashboard
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  # coturn ports (3478/5349 and relay range) are opened automatically by
  # services.netbird.server.coturn when enabled.

  # ACME: TLS certificates via Let's Encrypt HTTP-01 challenge.
  # nginx virtualHost with enableACME = true triggers cert creation.
  # No Cloudflare DNS plugin needed — VPS has a public IP and can respond
  # to HTTP-01 challenges directly.
  security.acme = {
    acceptTerms = true;
    defaults.email = vars.adminEmail;
  };

  my.services.netbird.server.enable = true;

  system.stateVersion = "25.11";
}
