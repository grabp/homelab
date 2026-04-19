{ inputs, ... }:
{
  # nixos-25.11 ships netbird 0.60.2 which is protocol-incompatible with the
  # 0.68.x management server running on this VPS. Override with unstable.
  nixpkgs.overlays = [
    (final: prev: {
      inherit (inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.system}) netbird;
    })
  ];

  # Setup key is used once (manually) to register VPS as a peer.
  # Available at /run/secrets/netbird/setup_key after deploy.
  sops.secrets."netbird/setup_key" = { };

  # NetBird peer client — gives VPS an overlay IP so Alloy can reach pebble Loki.
  # No routing features: VPS only needs point-to-point access to pebble, not routing.
  # ManagementURL is NOT set here: same Go url.URL unmarshalling gotcha as pebble.
  # Set once manually after first deploy via:
  #   sudo netbird-wt0 up --management-url https://netbird.DOMAIN \
  #     --setup-key $(sudo cat /run/secrets/netbird/setup_key)
  services.netbird.clients.wt0 = {
    port = 51820;
    openFirewall = true;
    ui.enable = false;
  };
}
