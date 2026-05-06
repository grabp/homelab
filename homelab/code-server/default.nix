# homelab/code-server/default.nix — code-server (VS Code in browser)
#
# OCI container (lscr.io/linuxserver/code-server) with a configurable
# workspace path. Intended for editing Home Assistant configuration files
# but usable for any host directory.
#
# Proxied by Caddy on pebble: https://code.grab-lab.gg → localhost:8484
#
# PRE-DEPLOY (pebble):
#   just edit-secrets-pebble → add:
#     code-server/env: |
#       PASSWORD=<your-password>
{
  config,
  lib,
  vars,
  ...
}:

let
  cfg = config.my.services.codeServer;
in
{
  options.my.services.codeServer = {
    enable = lib.mkEnableOption "code-server (VS Code in browser)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8484;
      description = "code-server web port (bound to loopback, proxied by Caddy).";
    };

    workspacePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/homeassistant";
      description = ''
        Host path mounted as the default workspace inside code-server.
        The path is mounted at the same location inside the container so
        absolute paths in the terminal match the host filesystem.
        Defaults to the Home Assistant config directory.
      '';
    };

    puid = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        PUID for the code-server process inside the container.
        Must have read/write access to workspacePath.
        Defaults to 0 (root) because HA config files are root-owned.
      '';
    };

    pgid = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "PGID for the code-server process. Must have access to workspacePath.";
    };
  };

  config = lib.mkIf cfg.enable {

    # code-server/env must contain:
    #   PASSWORD=<your-password>
    # Add with: just edit-secrets-pebble
    sops.secrets."code-server/env" = {
      mode = "0400";
      restartUnits = [ "podman-code-server.service" ];
    };

    # /var/lib/code-server holds VS Code extensions and user settings.
    # Separate from workspacePath so extensions survive workspace changes.
    systemd.tmpfiles.rules = [
      "d /var/lib/code-server 0750 root root -"
    ];

    virtualisation.oci-containers.containers.code-server = {
      image = "lscr.io/linuxserver/code-server:latest@sha256:35cc23ca91d088d00e0fa2bcd70891b0a70270937be8f8922e610132e2430c23";
      # Bind to loopback — Caddy is the only consumer, no LAN exposure needed.
      ports = [ "127.0.0.1:${toString cfg.port}:8443" ];
      volumes = [
        "/var/lib/code-server:/config"
        # Same path inside and outside the container so absolute paths match.
        "${cfg.workspacePath}:${cfg.workspacePath}"
      ];
      environment = {
        TZ = vars.timeZone;
        PUID = toString cfg.puid;
        PGID = toString cfg.pgid;
        DEFAULT_WORKSPACE = cfg.workspacePath;
      };
      # PASSWORD injected from sops secret — keeps it out of the Nix store.
      environmentFiles = [ config.sops.secrets."code-server/env".path ];
    };

    # Pattern 19: NixOS firewall reload flushes Netavark DNAT rules — restart
    # the container so its port mapping is re-registered.
    systemd.services.podman-code-server = {
      after = [ "firewall.service" ];
      partOf = [ "firewall.service" ];
    };
  };
}
