{ ... }: {
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # Required for deploy-rs: allow admin to push unsigned store paths
    trusted-users = [ "root" "admin" ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Allow unfree packages if needed
  nixpkgs.config.allowUnfree = false;
}
