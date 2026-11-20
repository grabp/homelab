# homelab/zigbee2mqtt/default.nix — Zigbee2MQTT bridge (native NixOS module)
#
# Native module: services.zigbee2mqtt (verified in nixpkgs 25.11).
# Owns the Zigbee coordinator USB stick exclusively — /dev/ttyUSB0 was removed
# from the Home Assistant container when this module was added. ZHA and
# Zigbee2MQTT cannot share one coordinator.
#
# Devices are exposed to Home Assistant through MQTT discovery on Mosquitto,
# not through a HA integration config. HA needs only the MQTT integration.
#
# Secrets live in an env file because the NixOS module serialises `settings`
# into the world-readable Nix store. Zigbee2MQTT reads ZIGBEE2MQTT_CONFIG_*
# env overrides (dist/util/settings.js: applyEnvironmentVariables), so the
# MQTT password and the Zigbee network key never enter the store.
#
# The module's preStart copies configuration.yaml from the store on every
# start, which wipes anything Zigbee2MQTT wrote back into it. That is why
# network_key / pan_id / ext_pan_id MUST be pinned (via the env file) rather
# than left as "GENERATE" — a regenerated key means re-pairing every device.
#
# PRE-DEPLOY (both steps required, in order):
#   1. just edit-secrets-pebble → add zigbee2mqtt/env in env-file format:
#        ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=<plaintext password>
#        ZIGBEE2MQTT_CONFIG_ADVANCED_NETWORK_KEY=[<16 comma-separated bytes>]
#        ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID=<1-65534>
#        ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID=[<8 comma-separated bytes>]
#      This deployment MIGRATES an existing ZHA network, so the last three are
#      read out of the ZHA coordinator backup — do NOT generate them (see the
#      Migration section of README.md):
#        scripts/hex2bytes.py -f <zha-backup>.json -k network_key -e
#        scripts/hex2bytes.py -f <zha-backup>.json -k ext_pan_id  -e
#        python3 -c 'import json,sys;print(int(json.load(open(sys.argv[1]))["network_info"]["pan_id"],16))' <zha-backup>.json
#      Only for a brand new network with nothing paired yet, generate instead:
#        python3 -c 'import secrets;print("["+",".join(str(b) for b in secrets.token_bytes(16))+"]")'
#   2. Hash that same password for Mosquitto and paste it into
#      homelab/mosquitto/default.nix (zigbee2mqtt user):
#        nix shell nixpkgs#mosquitto --command mosquitto_passwd -c -b /tmp/p zigbee2mqtt '<password>'
#        cat /tmp/p   # take the part after "zigbee2mqtt:"
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.services.zigbee2mqtt;
in
{
  options.my.services.zigbee2mqtt = {
    enable = lib.mkEnableOption "Zigbee2MQTT bridge";

    port = lib.mkOption {
      type = lib.types.port;
      # 8080 is docs-site, 8083 calibre-web, 8089 loki — 8090 is free.
      default = 8090;
      description = "Zigbee2MQTT web frontend port (localhost only; Caddy proxies here).";
    };

    serialPort = lib.mkOption {
      type = lib.types.str;
      default = "/dev/ttyUSB0";
      description = ''
        Zigbee coordinator serial device. Prefer a stable
        /dev/serial/by-id/... path if a second USB serial device is ever added,
        since ttyUSB enumeration order is not guaranteed across reboots.
      '';
    };

    adapter = lib.mkOption {
      type = lib.types.enum [
        "deconz"
        "zstack"
        "zigate"
        "ezsp"
        "ember"
        "zboss"
        "zoh"
      ];
      # HA Connect ZBT-1 (ex-SkyConnect) is a Silabs EFR32 running EmberZNet.
      # "ember" is the current driver; "ezsp" is the legacy one that autodetect
      # can still land on, and it behaves worse with this stick.
      default = "ember";
      description = "Zigbee adapter driver. Set explicitly — autodetect is unreliable.";
    };

    rtscts = lib.mkOption {
      type = lib.types.bool;
      # ZBT-1 EmberZNet firmware uses hardware flow control: bellows read
      # flow_control = "hardware" from the firmware itself (XNCP
      # get_flow_control_type) into the ZHA backup metadata. With rtscts off,
      # the ember driver falls back to XON/XOFF (zigbee-herdsman ash.js), which
      # this firmware never sends.
      default = true;
      description = "RTS/CTS hardware flow control on the coordinator serial port.";
    };

    channel = lib.mkOption {
      type = lib.types.int;
      # Channel 25 — matches the ZHA network migrated from (ZHA backup
      # 2026-11-20, network_info.channel). Do not change: devices stay on the
      # channel the coordinator formed the network on.
      default = 25;
      description = ''
        Zigbee radio channel. MUST match the network being migrated from —
        read it out of the ZHA coordinator backup (network_info.channel).
        A mismatch here looks exactly like a dead coordinator: devices are
        joined but never answer.
      '';
    };

    mqttUser = lib.mkOption {
      type = lib.types.str;
      default = "zigbee2mqtt";
      description = "Mosquitto username (password comes from the sops env file).";
    };
  };

  config = lib.mkIf cfg.enable {

    services.zigbee2mqtt = {
      enable = true;

      settings = {
        # HA MQTT discovery — the module's default ties this to
        # services.home-assistant.enable, which is false here because HA runs
        # as an OCI container. Must be set explicitly.
        homeassistant.enabled = true;

        # Pairing stays off; enable it from the frontend only while adding a
        # device. A permanently open network lets any device join.
        permit_join = false;

        mqtt = {
          base_topic = "zigbee2mqtt";
          # Explicit IPv4 — Mosquitto listens on 0.0.0.0, and "localhost" can
          # resolve to ::1 on this dual-stack host.
          server = "mqtt://127.0.0.1:${toString config.my.services.mosquitto.port}";
          user = cfg.mqttUser;
          # password: ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD (env file)
        };

        serial = {
          port = cfg.serialPort;
          adapter = cfg.adapter;
          rtscts = cfg.rtscts;
        };

        frontend = {
          enabled = true;
          # Bind to loopback — Caddy terminates TLS and the frontend has no auth.
          host = "127.0.0.1";
          port = cfg.port;
        };

        advanced = {
          log_level = "info";
          channel = cfg.channel;
          # network_key / pan_id / ext_pan_id: set via env file (see header).
        };

        availability.enabled = true;
      };
    };

    # ── Sops secret: MQTT password + Zigbee network identity as env file ──────
    sops.secrets."zigbee2mqtt/env" = {
      owner = "zigbee2mqtt";
      mode = "0400";
      restartUnits = [ "zigbee2mqtt.service" ];
    };

    systemd.services.zigbee2mqtt = {
      serviceConfig.EnvironmentFile = [ config.sops.secrets."zigbee2mqtt/env".path ];
      # Mosquitto must be up first: Zigbee2MQTT exits on a failed initial
      # MQTT connect, and Restart=on-failure would churn until the broker is up.
      after = [
        "sops-install-secrets.service"
        "mosquitto.service"
      ];
      wants = [
        "sops-install-secrets.service"
        "mosquitto.service"
      ];
    };

    # Frontend is loopback-only — no firewall port. Caddy reaches it on 127.0.0.1.
  };
}
