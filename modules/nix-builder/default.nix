{ config, lib, ... }:

let
  cfg = config.my.builder;
in
{
  options.my.builder = {
    enable = lib.mkEnableOption "Nix remote builder (accept delegated builds from other machines)";

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys authorized to connect as the nixremote user for remote builds.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.nixremote = {
      isSystemUser = true;
      group = "nixremote";
      useDefaultShell = true;
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };
    users.groups.nixremote = { };

    # trusted-users allows the remote Nix client to push unsigned store paths
    # and perform builds without signature verification errors.
    nix.settings.trusted-users = [ "nixremote" ];
  };
}
