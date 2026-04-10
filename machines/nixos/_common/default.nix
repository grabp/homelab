{ ... }: {
  imports = [
    ./nix-settings.nix
    ./ssh.nix
    ./users.nix
    ./locale.nix
  ];
}
