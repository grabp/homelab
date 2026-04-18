# homelab/home-assistant/default.nix — Home Assistant + HACS + ESPHome (Stage 9a/9b)
#
# Podman OCI container (not services.home-assistant native module).
# Reason: upstream treats NixOS as unsupported; native module freezes HA at
# branch-off and misses monthly updates. OCI container tracks stable channel.
#
# Network mode: --network=host — required for mDNS device discovery
# (Zigbee, Chromecast, UniFi, etc.). Container uses host IP stack directly.
#
# HACS: installed via systemd oneshot before the container starts (Pattern 11,
# Approach A — download latest on first boot, idempotent).
#
# ESPHome: Podman OCI container with --network=host. Co-located here because
# it is part of the HA ecosystem. Native services.esphome has three unresolved
# packaging bugs (DynamicUser path, missing pyserial, missing font component).
#
# Avahi: enabled for mDNS — ESPHome, Matter Server, and HA use --network=host
# and rely on .local resolution for device discovery.
#
# ⚠ POST-DEPLOY STEPS:
#   1. Browse to https://ha.grab-lab.gg and complete the onboarding wizard.
#   2. Settings → Devices & Services → Add Integration → HACS
#      Complete the GitHub OAuth device flow in the browser.
#   3. Add MQTT integration: server 127.0.0.1, port 1883,
#      user "homeassistant", password set via mosquitto_passwd.
#   4. UniFi integration requires a local admin account on the controller
#      (not an SSO/cloud account).
#   5. (Stage 9b) ESPHome: Settings → Devices & Services → ESPHome
#      → Add Integration → host 127.0.0.1, port 6052
#   6. (Stage 9b) Voice assistants: create pipeline using Wyoming endpoints.
{ config, lib, pkgs, vars, ... }:

let
  cfg = config.my.services.homeAssistant;
in
{
  options.my.services.homeAssistant = {
    enable = lib.mkEnableOption "Home Assistant (Podman OCI container)";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 8123;
      description = "Home Assistant web UI port (host network)";
    };

    image = lib.mkOption {
      type    = lib.types.str;
      default = "ghcr.io/home-assistant/home-assistant:stable";
      description = "OCI image tag — pin to a specific release for reproducibility, e.g. 2026.4.3";
    };

    configDir = lib.mkOption {
      type    = lib.types.str;
      default = "/var/lib/homeassistant";
      description = "Host path for persistent HA configuration";
    };

    # ESPHome dashboard — co-located here because it is part of the HA ecosystem.
    # Native services.esphome has three unresolved bugs; use the OCI container.
    esphome = {
      enable = lib.mkEnableOption "ESPHome dashboard (Podman OCI container, co-located with HA)";

      port = lib.mkOption {
        type    = lib.types.port;
        default = 6052;
        description = "ESPHome dashboard port (host network)";
      };

      image = lib.mkOption {
        type    = lib.types.str;
        default = "ghcr.io/esphome/esphome:2026.3.1";
        description = "OCI image tag — pin to a specific release for reproducibility";
      };

      configDir = lib.mkOption {
        type    = lib.types.str;
        default = "/var/lib/esphome";
        description = "Host path for persistent ESPHome device configurations";
      };
    };
  };

  # lib.mkMerge is required when using multiple lib.mkIf blocks at the config
  # level — the same pattern as homelab/netbird/default.nix (Pattern 14).
  config = lib.mkMerge [

    # === Home Assistant (always active when my.services.homeAssistant.enable = true) ===
    (lib.mkIf cfg.enable {

      # Create config dir and ensure configuration.yaml has the http proxy block.
      # Two cases handled:
      #   1. File does not exist (fresh deploy): write a minimal config with http block.
      #   2. File exists but lacks "http:" key (e.g. restored from backup): append the block.
      # Idempotent — if "http:" is already present, nothing is modified.
      # Note: after a backup restore, restart the container for HA to pick up the change:
      #   podman restart homeassistant
      system.activationScripts.ha-init-config = lib.stringAfter [ "var" ] ''
        mkdir -p ${cfg.configDir}/custom_components

        if [ ! -f ${cfg.configDir}/configuration.yaml ]; then
          cat > ${cfg.configDir}/configuration.yaml <<'EOF'
# Home Assistant Configuration
# https://www.home-assistant.io/docs/configuration/

# Trust the Caddy reverse proxy so client IPs are forwarded correctly.
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - ::1

default_config:
EOF
        elif ! grep -q "^http:" ${cfg.configDir}/configuration.yaml; then
          cat >> ${cfg.configDir}/configuration.yaml <<'EOF'

# Trust the Caddy reverse proxy so client IPs are forwarded correctly.
# (injected by NixOS activation script — safe to move/edit)
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - ::1
EOF
        fi
      '';

      # HACS installation — runs once before the HA container starts.
      # Idempotent: skipped if __init__.py already exists (i.e. HACS is installed).
      # Pattern 11 (Approach A) from docs/NIX-PATTERNS.md.
      systemd.services.hacs-install = {
        description = "Install HACS custom component for Home Assistant";
        wantedBy    = [ "multi-user.target" ];
        before      = [ "podman-homeassistant.service" ];
        requiredBy  = [ "podman-homeassistant.service" ];
        path        = with pkgs; [ wget unzip coreutils ];
        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          HACS_DIR="${cfg.configDir}/custom_components/hacs"
          if [ ! -f "$HACS_DIR/__init__.py" ]; then
            echo "Installing HACS..."
            wget -q -O /tmp/hacs.zip \
              "https://github.com/hacs/integration/releases/latest/download/hacs.zip"
            rm -rf "$HACS_DIR"
            mkdir -p "$HACS_DIR"
            unzip -o /tmp/hacs.zip -d "$HACS_DIR"
            rm -f /tmp/hacs.zip
            echo "HACS installed."
          else
            echo "HACS already present, skipping."
          fi
        '';
      };

      virtualisation.oci-containers.containers.homeassistant = {
        image     = cfg.image;
        autoStart = true;

        volumes = [
          "${cfg.configDir}:/config"
          "/etc/localtime:/etc/localtime:ro"
        ];

        environment = {
          TZ = vars.timeZone;
        };

        # --network=host: required for mDNS (Zigbee, Chromecast, UniFi, etc.)
        # --privileged: required for hardware access (USB, Bluetooth, raw sockets)
        extraOptions = [
          "--network=host"
          "--privileged"
        ];
      };

      # Start HA after Mosquitto is ready (soft dependency — HA works without MQTT,
      # but prefer Mosquitto to be up before HA tries to connect on boot).
      systemd.services.podman-homeassistant = {
        wants = [ "mosquitto.service" ];
        after = [ "mosquitto.service" ];
      };

      # 8123 is served on the host network stack directly (--network=host).
      networking.firewall.allowedTCPPorts = [ cfg.port ];

      # Avahi mDNS — required for ESPHome device discovery and .local resolution.
      # Use nssmdns4 (not nssmdns) to avoid slow lookups for non-.local domains.
      # ESPHome and Matter Server containers (--network=host) rely on this.
      services.avahi = {
        enable      = true;
        nssmdns4    = true;
        openFirewall = true;   # Opens UDP 5353 for mDNS multicast
        publish = {
          enable    = true;
          addresses = true;
        };
      };
    })

    # === ESPHome (only when cfg.esphome.enable = true) ===
    (lib.mkIf (cfg.enable && cfg.esphome.enable) {

      virtualisation.oci-containers.containers.esphome = {
        image     = cfg.esphome.image;
        autoStart = true;

        # --network=host: required for mDNS device discovery
        extraOptions = [ "--network=host" ];

        volumes = [
          "${cfg.esphome.configDir}:/config"
          "/etc/localtime:/etc/localtime:ro"
        ];

        environment = {
          TZ = vars.timeZone;
        };
      };

      # ESPHome needs Avahi mDNS running before it can discover ESP devices.
      # (Pattern 16C in docs/NIX-PATTERNS.md — soft start ordering)
      systemd.services.podman-esphome = {
        wants = [ "avahi-daemon.service" ];
        after = [ "avahi-daemon.service" ];
      };

      # Persistent state directory for ESPHome device configs and compiled firmware.
      systemd.tmpfiles.rules = [
        "d ${cfg.esphome.configDir} 0755 root root -"
      ];

      # 6052 is on the host network stack (--network=host); Caddy proxies it.
      networking.firewall.allowedTCPPorts = [ cfg.esphome.port ];
    })

  ];
}
