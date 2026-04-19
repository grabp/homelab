{ ... }:
{
  # Fail2ban: SSH brute-force protection on both pebble and VPS.
  # Loaded via _common/default.nix — applies to every machine in this flake.
  services.fail2ban = {
    enable   = true;
    maxretry = 5;
    bantime  = "10m";

    jails.sshd.settings = {
      enabled  = true;
      maxretry = 3;      # stricter than global maxretry for SSH
    };
  };
}
