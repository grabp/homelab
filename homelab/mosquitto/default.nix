# homelab/mosquitto/default.nix — Mosquitto MQTT broker (Stage 9a)
#
# Native NixOS module: services.mosquitto
# Port: 1883/tcp — LAN (IoT devices) + localhost (Home Assistant)
# Auth: Per-listener password authentication with pre-hashed passwords
#
# Gotcha: the NixOS module sets per_listener_settings = true globally, so
# users and ACLs must be defined per listener, not at the top level.
#
# ⚠ BEFORE DEPLOYING: Generate and replace the placeholder hashedPassword.
#   Run on pebble (or any machine with mosquitto):
#     nix shell nixpkgs#mosquitto --command mosquitto_passwd -c /tmp/p homeassistant
#     cat /tmp/p   # output: "homeassistant:<hash>" — paste the hash below
#   Then add a second user for IoT devices if needed.
{ config, lib, ... }:

let
  cfg = config.my.services.mosquitto;
in
{
  options.my.services.mosquitto = {
    enable = lib.mkEnableOption "Mosquitto MQTT broker";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      description = "MQTT listener port";
    };
  };

  config = lib.mkIf cfg.enable {
    services.mosquitto = {
      enable = true;
      listeners = [
        {
          port = cfg.port;
          # Bind to all interfaces so both HA (--network=host) and LAN IoT devices connect.
          # The firewall restricts external access — see networking.firewall below.
          address = "0.0.0.0";
          users = {
            homeassistant = {
              acl = [ "readwrite #" ];
              # ⚠ Replace with a real hash before deploying — see instructions above.
              # The service will reject auth (but still start) until a valid hash is set.
              hashedPassword = "$7$101$J0EXRr5XXVpwRqJy$YdlvpxnMuVs4eTDIONJcX4t6AYQkcWhQ4Fv2BDbxlzLdqdS+YW46LtAIXgaGcPbX2zNHA5Hu9vsB5jU6WEp53Q==";
            };
          };
        }
      ];
    };

    # MQTT is LAN-only — no Caddy vhost, no internet exposure.
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
