{ ... }: {
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";

      # Verbose logging required for fail2ban to parse auth failures
      LogLevel = "VERBOSE";

      # Disable unused forwarding features (attack surface reduction)
      X11Forwarding = false;
      AllowTcpForwarding = false;
      AllowAgentForwarding = false;

      # Limit auth attempts and concurrent sessions
      MaxAuthTries = 3;
      MaxSessions = 2;

      # Disconnect idle sessions after 10 minutes (300s × 2 missed keepalives)
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;

      # Mozilla Modern spec — only AEAD ciphers, ETM-only MACs, Curve25519 KEX
      KexAlgorithms = [
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
      ];
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
      ];
      Macs = [
        "hmac-sha2-256-etm@openssh.com"
        "hmac-sha2-512-etm@openssh.com"
        "umac-128-etm@openssh.com"
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
}
