{ config, lib, ... }:

let
  cfg = config.my.networking.staticIPv4;
in
{
  options.my.networking.staticIPv4 = {
    enable = lib.mkEnableOption "static IPv4 address";

    address = lib.mkOption {
      type = lib.types.str;
      description = "Static IPv4 address";
      example = "192.168.10.50";
    };

    prefixLength = lib.mkOption {
      type = lib.types.int;
      default = 24;
      description = "Network prefix length (subnet mask)";
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      description = "Default gateway address";
      example = "192.168.10.1";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "Network interface name. Check with: ip link show";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "DNS nameservers. After Stage 3 (Pi-hole), set to [ \"127.0.0.1\" ]";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.useDHCP = false;

    networking.interfaces.${cfg.interface}.ipv4.addresses = [
      {
        address = cfg.address;
        prefixLength = cfg.prefixLength;
      }
    ];

    networking.defaultGateway = cfg.gateway;
    networking.nameservers = cfg.nameservers;
  };
}
