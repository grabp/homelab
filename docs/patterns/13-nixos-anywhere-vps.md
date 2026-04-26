---
kind: pattern
number: 13
tags: [vps, nixos-anywhere, provisioning, ext4]
---

# Pattern 13: nixos-anywhere VPS provisioning with minimal ext4 disko

`nixos-anywhere` kexec-boots into a NixOS installer in RAM, partitions via disko, and installs your flake — all from one SSH command. Requires ≥1 GB RAM on the target. Works on Hetzner, DigitalOcean, Vultr, and any VPS offering root SSH access.

```bash
# Initial provisioning (run from dev machine after creating VPS)
nix run github:nix-community/nixos-anywhere -- --flake .#vps root@<VPS_IP>

# Subsequent updates via deploy-rs
nix run github:serokell/deploy-rs -- -s .#vps
# or via justfile:
# just deploy-vps
```

```nix
# machines/nixos/vps/disko.nix — simple ext4, no ZFS needed on VPS
{
  disko.devices.disk.main = {
    device = "/dev/sda";  # ⚠️ VERIFY: Hetzner CX22 uses /dev/sda; check with lsblk
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "512M";
          content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; };
        };
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };
  };
}
```

```nix
# machines/nixos/vps/default.nix — minimal VPS base config
# Note: netbird-server.nix uses OCI containers (virtualisation.oci-containers),
# NOT services.netbird.server — see Pattern 19 for the OCI container approach.
# ⚠️ services.netbird.server exists but is not production-ready as of nixos-25.11.
{ vars, ... }: {
  imports = [ ./disko.nix ./netbird-server.nix ];

  networking.hostName = "vps";

  # UEFI via systemd-boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # sops: VPS decrypts with its own SSH host key
  sops = {
    defaultSopsFile = ../../../secrets/vps.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  # Firewall: NetBird control plane ports + restricted SSH
  networking.firewall = {
    allowedTCPPorts = [ 80 443 ];
    allowedUDPPorts = [ 3478 ];
    allowedUDPPortRanges = [{ from = 49152; to = 65535; }];
  };

  # ACME/Let's Encrypt for netbird.grab-lab.gg
  security.acme = {
    acceptTerms = true;
    defaults.email = vars.adminEmail;
  };

  system.stateVersion = "25.11";
}
```

**Source:** nixos-anywhere README (github:nix-community/nixos-anywhere) ✅. disko ext4 from Pattern 4 ✅. `allowedUDPPortRanges` verified in NixOS options ✅.
