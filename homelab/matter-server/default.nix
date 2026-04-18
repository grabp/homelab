# homelab/matter-server/default.nix — Matter Server (Stage 9b)
#
# Podman OCI container (not services.matter-server native module).
# Reason: CHIP SDK (home-assistant-chip-core) requires architecture-specific
# binary wheels with a non-standard build system (CIPD + GN); building natively
# on NixOS is extremely difficult (nixpkgs #255774). The Docker image bundles them.
#
# Network mode: --network=host — mandatory.
#   Matter uses IPv6 link-local multicast for device discovery. Bridge networking
#   completely breaks device discovery.
#
# ⚠ IPv6 forwarding MUST be disabled (net.ipv6.conf.all.forwarding = 0):
#   If IPv6 forwarding is enabled, Matter devices experience up to 30-minute
#   reachability outages on network changes. IPv4 forwarding (used by NetBird
#   routing) is a separate sysctl and is not affected.
#
# HA integration (after deploy):
#   Settings → Devices & Services → Add Integration → Matter
#   WebSocket URL: ws://127.0.0.1:5580/ws
{ config, lib, vars, ... }:

let
  cfg = config.my.services.matterServer;
in
{
  options.my.services.matterServer = {
    enable = lib.mkEnableOption "Matter Server (Podman OCI container)";

    image = lib.mkOption {
      type    = lib.types.str;
      default = "ghcr.io/home-assistant-libs/python-matter-server:stable";
      description = "OCI image tag — pin to a specific version (e.g. 8.1.2) for reproducibility";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.matter-server = {
      image     = cfg.image;
      autoStart = true;

      # --network=host: Matter IPv6 link-local multicast needs the host network stack.
      # --security-opt=label=disable: required for Bluetooth commissioning via D-Bus.
      extraOptions = [
        "--network=host"
        "--security-opt=label=disable"
      ];

      volumes = [
        "/var/lib/matter-server:/data"
        "/run/dbus:/run/dbus:ro"
      ];

      environment = {
        TZ = vars.timeZone;
      };
    };

    # Matter requires Avahi mDNS to be running before it can discover devices.
    # (Pattern 16C in docs/NIX-PATTERNS.md — soft start ordering)
    systemd.services.podman-matter-server = {
      wants = [ "avahi-daemon.service" ];
      after = [ "avahi-daemon.service" ];
    };

    # Persistent state directory for Matter fabric credentials and device data.
    systemd.tmpfiles.rules = [
      "d /var/lib/matter-server 0755 root root -"
    ];

    # Matter requires IPv6 for link-local multicast device discovery.
    networking.enableIPv6 = true;

    # IPv6 forwarding must be DISABLED — enabled forwarding causes Matter devices
    # to go unreachable for up to 30 minutes after network changes.
    # This does not conflict with NetBird's IPv4 routing (net.ipv4.ip_forward).
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkDefault 0;

    # Port 5580: Matter WebSocket API (HA connects on localhost; open for LAN diagnostics).
    networking.firewall.allowedTCPPorts = [ 5580 ];
  };
}
