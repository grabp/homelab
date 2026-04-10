{ ... }: {
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      # Use only modern, secure key exchange algorithms
      KexAlgorithms = [
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
}
