{ lib, vars, ... }: {
  imports = [
    ./disko.nix
    ./netbird-server.nix
    ./caddy.nix
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
  # Caddy for ACME HTTP-01 challenge and NetBird dashboard/API
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  # coturn ports (3478/5349 and relay range) are opened automatically by services.coturn.

  # ACME: Caddy obtains TLS certs via Let's Encrypt HTTP-01 challenge.
  # No Cloudflare DNS plugin needed — VPS has a public IP.
  # acceptTerms + email are read by the Caddy module as ACME defaults.
  security.acme = {
    acceptTerms = true;
    defaults.email = vars.adminEmail;
  };

  my.services.netbird.server.enable = true;

  system.stateVersion = "25.11";
}
