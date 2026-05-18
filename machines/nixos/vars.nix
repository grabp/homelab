let
  local = if builtins.pathExists ./local.nix then import ./local.nix else { };
in
{
  domain = "grab-lab.gg";
  pebbleIP = "192.168.10.50";
  boulderIP = "192.168.10.51"; # HP EliteDesk 705 G4 (media/productivity server)
  vpsIP =
    local.vpsIP or (throw "VPS IP not set: create machines/nixos/local.nix (run: just setup-local)");
  routerIP = "192.168.1.1";
  adminEmail = "admin@grab-lab.gg";
  timeZone = "Europe/Warsaw";
  nasIP = "192.168.10.100"; # Synology NAS
}
