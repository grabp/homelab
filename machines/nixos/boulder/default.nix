{ vars, ... }:
{
  imports = [
    ./disko.nix
    ./hardware.nix
  ];

  # Secrets management via sops-nix
  sops = {
    defaultSopsFile = ../../../secrets/boulder.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  networking.hostName = "boulder";

  # ZFS requires a unique hostId — generated with:
  # head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
  networking.hostId = "72b51f0c";

  # ZFS configuration
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = true;
  boot.kernelParams = [
    "nohibernate"
    "zfs.zfs_arc_max=8589934592" # Cap ARC at 8GB (32GB total, leaving ~24GB for services)
  ];

  # ZFS maintenance
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  # UEFI boot via systemd-boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Static IP networking
  my.networking.staticIPv4 = {
    enable = true;
    address = vars.boulderIP;
    prefixLength = 24;
    gateway = "192.168.10.1";
    # Pi-hole on pebble as primary DNS; Cloudflare fallback
    nameservers = [
      vars.pebbleIP
      "1.1.1.1"
    ];
  };

  # Firewall — default deny, SSH allowed via _common/ssh.nix
  networking.firewall.enable = true;

  # systemd-resolved for NetBird DNS routing
  # DNSStubListener=no frees port 53 (Pattern 15)
  services.resolved = {
    enable = true;
    extraConfig = ''
      DNSStubListener=no
    '';
  };

  my.services.postgresql.enable = true; # Stage 12

  my.services.netbird.enable = true; # Stage 11
  my.services.nodeExporter.enable = true; # Stage 11
  my.services.alloy = {
    enable = true;
    hostLabel = "boulder";
    lokiUrl = "https://${vars.pebbleIP}:3100/loki/api/v1/push"; # LAN — no NetBird hop needed
    insecureSkipVerify = true;
  }; # Stage 11
  my.services.backup.enable = true;

  system.stateVersion = "25.11";
}
