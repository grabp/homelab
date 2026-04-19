{ ... }:
{
  # Fail2ban: SSH brute-force protection on both pebble and VPS.
  # Loaded via _common/default.nix — applies to every machine in this flake.
  services.fail2ban = {
    enable   = true;
    maxretry = 5;
    bantime  = "10m";

    # Progressive banning: each repeat offender gets an exponentially longer ban.
    # Multipliers: 10m → 20m → 40m → 80m → 160m → 320m → 640m, capped at 1 week.
    bantime-increment = {
      enable      = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime     = "168h"; # 1 week
    };

    # Never ban NetBird overlay range — locking yourself out of VPN is bad.
    ignoreIP = [ "100.64.0.0/10" ];

    jails.sshd.settings = {
      enabled  = true;
      maxretry = 3;      # stricter than global maxretry for SSH
    };
  };
}
