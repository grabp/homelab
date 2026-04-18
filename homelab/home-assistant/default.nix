# homelab/home-assistant/default.nix — Home Assistant + HACS (Stage 9a)
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
# ⚠ POST-DEPLOY STEPS:
#   1. Browse to https://ha.grab-lab.gg and complete the onboarding wizard.
#   2. Settings → Devices & Services → Add Integration → HACS
#      Complete the GitHub OAuth device flow in the browser.
#   3. Add MQTT integration: server 127.0.0.1, port 1883,
#      user "homeassistant", password set via mosquitto_passwd.
#   4. UniFi integration requires a local admin account on the controller
#      (not an SSO/cloud account).
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
  };

  config = lib.mkIf cfg.enable {
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
    # The firewall must permit it for LAN clients and the Caddy reverse proxy.
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
