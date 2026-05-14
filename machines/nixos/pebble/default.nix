{ vars, ... }:
{
  imports = [
    ./disko.nix
    ./hardware.nix
  ];

  # Secrets management via sops-nix
  sops = {
    defaultSopsFile = ../../../secrets/pebble.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
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
    "zfs.zfs_arc_max=4294967296" # Cap ARC at 4GB, leaving ~12GB for services
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
    address = vars.pebbleIP;
    prefixLength = 24;
    gateway = "192.168.10.1";
    # Pi-hole primary; 1.1.1.1 fallback for pebble's own lookups
    # (avoids ACME/deploy failures when Pi-hole restarts during nixos-rebuild)
    nameservers = [
      "127.0.0.1"
      "1.1.1.1"
    ];
  };

  # Firewall — default deny, SSH allowed via _common/ssh.nix
  networking.firewall.enable = true;
  # Loki: accept log pushes from two sources.
  # wg0 (WireGuard): VPS Alloy pushes over the mesh (not on LAN).
  # eth0 (LAN): boulder Alloy pushes directly.
  # wg0 rule is in homelab/wireguard/default.nix (routing = true).
  networking.firewall.interfaces."eth0".allowedTCPPorts = [ 3100 ];

  my.services.pihole.enable = true;
  my.services.caddy.enable = true;
  my.services.vaultwarden.enable = true;

  my.services.prometheus.enable = true; # Stage 6
  my.services.grafana.enable = true;
  my.services.loki.enable = true;
  my.services.wireguard = {
    enable = true;
    address = "10.10.0.2/32";
    routing = true; # advertises 192.168.10.0/24 to the WireGuard mesh
  }; # Stage 7b
  my.services.kanidm.enable = true; # Stage 7c
  my.services.homepage.enable = true; # Stage 8
  my.services.mosquitto.enable = true; # Stage 9a
  my.services.homeAssistant.enable = true; # Stage 9a
  my.services.homeAssistant.homekitPorts = [
    21064
    21065
  ]; # two HomeKit bridges
  my.services.homeAssistant.esphome.enable = true; # Stage 9b
  my.services.uptimeKuma.enable = true; # Stage 9a
  my.services.wyoming.enable = true; # Stage 9b
  my.services.matterServer.enable = true; # Stage 9b
  my.services.backup.enable = true; # Stage 10
  my.services.docsSite.enable = true; # Stage 11
  my.services.codeServer = {
    enable = true;
    workspacePath = "/var/lib/homeassistant"; # default, but explicit
  };

  # Prometheus: scrape boulder's node_exporter over LAN (Stage 11)
  # job_name must differ from "node" (used by pebble's own exporter in homelab/prometheus/default.nix)
  services.prometheus.scrapeConfigs = [
    {
      job_name = "node_boulder";
      static_configs = [ { targets = [ "${vars.boulderIP}:9100" ]; } ];
    }
  ];

  system.stateVersion = "25.11";
}
