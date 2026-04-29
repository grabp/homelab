{ config, lib, ... }:

let
  cfg = config.my.services.nodeExporter;
in
{
  options.my.services.nodeExporter = {
    enable = lib.mkEnableOption "Prometheus node_exporter";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port node_exporter listens on";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for node_exporter. Set to false when only scraped locally.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
      listenAddress = "0.0.0.0";
      port = cfg.port;
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
