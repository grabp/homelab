# homelab/docs-site/default.nix — MkDocs documentation portal
#
# Serves the repo's docs/ tree as a navigable web portal.
# Built with Material for MkDocs theme.
#
# Stage: 11 (Phase 2 prep)
# Ports: 8080 (Caddy proxies docs.grab-lab.gg → 127.0.0.1:8080)
# DNS: docs.grab-lab.gg (via homelab/pihole/default.nix customDNS)
# Secrets: none
#
# Caddy integration: Add @docs handle block to homelab/caddy/default.nix
# Pi-hole integration: Add customDNS entry to homelab/pihole/default.nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.docsSite;
  vars = import ../../machines/nixos/vars.nix;

  # Build the static site from the repo root
  # mkdocs.yml lives at the repo root, docs/ lives at repo root
  docsSite = pkgs.stdenv.mkDerivation {
    name = "homelab-docs-site";
    src = ../..;  # repo root

    nativeBuildInputs = with pkgs; [
      python311
      python311Packages.mkdocs
      python311Packages.mkdocs-material
      python311Packages.pymdown-extensions
    ];

    buildPhase = ''
      export HOME=$(mktemp -d)
      mkdocs build --strict --site-dir $out
    '';

    installPhase = ''
      # Output is already in $out from buildPhase
      echo "Site built to $out"
    '';
  };
in
{
  options.my.services.docsSite = {
    enable = lib.mkEnableOption "MkDocs documentation portal";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for nginx to serve the docs site";
    };
  };

  config = lib.mkIf cfg.enable {
    # Serve the built static site via nginx
    services.nginx = {
      enable = true;
      virtualHosts."docs.${vars.domain}" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = cfg.port;
          }
        ];
        locations."/" = {
          root = docsSite;
          extraConfig = ''
            add_header Cache-Control "public, max-age=300";
          '';
        };
      };
    };
  };
}
