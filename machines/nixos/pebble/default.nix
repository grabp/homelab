{ vars, ... }: {
  imports = [
    ./disko.nix
    ./hardware.nix
  ];

  # Secrets management via sops-nix
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "test_secret" = { };
    };
  };

  networking.hostName = "pebble";

  # ZFS requires a unique hostId — generate with:
  # head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
  networking.hostId = "8423e349";

  # ZFS configuration (see docs/ARCHITECTURE.md)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = true;
  boot.kernelParams = [
    "nohibernate"
    "zfs.zfs_arc_max=4294967296"  # Cap ARC at 4GB, leaving ~12GB for services
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
    address = vars.serverIP;
    prefixLength = 24;
    gateway = "192.168.10.1";
    # After Pi-hole is deployed (Stage 3), this resolves via localhost
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
  };

  # Firewall — default deny, SSH allowed via _common/ssh.nix
  networking.firewall.enable = true;

  # Services enabled in later stages:
  # my.services.pihole.enable = true;   # Stage 3
  # my.services.caddy.enable = true;    # Stage 4
  # my.services.grafana.enable = true;  # Stage 5
  # my.services.prometheus.enable = true;
  # my.services.loki.enable = true;
  # my.services.netbird.enable = true;  # Stage 6
  # my.services.homepage.enable = true; # Stage 7
  # my.services.homeAssistant.enable = true; # Stage 8
  # my.services.uptimeKuma.enable = true;

  system.stateVersion = "25.11";
}
