{ ... }: {
  imports = [
    ./nix-settings.nix
    ./ssh.nix
    ./users.nix
    ./locale.nix
    ./security.nix    # Stage 10: fail2ban on all machines
  ];
}
