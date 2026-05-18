{ lib, vars, ... }:
{
  imports = [
    ./disko.nix
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

  my.services.wireguardServer.enable = true; # Stage 7b — WireGuard VPN hub

  networking.firewall.enable = true;
  # WireGuard UDP 51820 opened by homelab/wireguard-server/default.nix.
  # SSH (22) opened by machines/nixos/_common/ssh.nix.
  # No other inbound ports needed.

  my.services.alloy = {
    enable = true;
    hostLabel = "vps";
    # Reach pebble Loki over the WireGuard tunnel (pebble advertises 192.168.10.0/24 via wg0)
    lokiUrl = "https://${vars.pebbleIP}:3100/loki/api/v1/push";
    insecureSkipVerify = true;
  }; # Stage 10

  # Node exporter — scraped by pebble Prometheus over WireGuard (10.10.0.1).
  # Not exposed on the public interface; wg0-scoped rule limits access to VPN peers only.
  my.services.nodeExporter = {
    enable = true;
    openFirewall = false;
  };
  networking.firewall.interfaces."wg0".allowedTCPPorts = [
    9100
    9586
  ];

  # WireGuard exporter — binds to VPN IP so pebble can scrape all peer handshake times,
  # including mobile clients (10.10.0.4+) which have no spoke-side exporter.
  services.prometheus.exporters.wireguard = {
    enable = true;
    listenAddress = "10.10.0.1";
    interfaces = [ "wg0" ];
  };

  system.stateVersion = "25.11";
}
