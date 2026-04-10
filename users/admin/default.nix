{ pkgs, ... }: {
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [
      "wheel"      # sudo access
      "podman"     # container management (Stage 3+)
    ];
    shell = pkgs.bash;

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGY7yfcUgzDRtAxxRe07DcXV8CpljRjYQWERAUETEE+E grabowskip@koksownik"
    ];
  };

  # Passwordless sudo for wheel group (key-based SSH auth only)
  security.sudo.wheelNeedsPassword = false;
}
