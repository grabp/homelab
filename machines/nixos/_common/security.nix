{ ... }:
{
  # Kernel hardening — applies to all machines (pebble + VPS + future boulder).
  # Note: net.ipv4.ip_forward is intentionally NOT set here — pebble's NetBird
  # routing peer requires it enabled, and the netbird module sets it via
  # services.netbird.useRoutingFeatures = "both".
  security.protectKernelImage = true;

  boot.kernel.sysctl = {
    # Drop packets arriving on the wrong interface (prevents IP spoofing).
    "net.ipv4.conf.all.rp_filter"        = 1;
    # Hide kernel symbol addresses from unprivileged processes.
    "kernel.kptr_restrict"                = 2;
    # Restrict dmesg to root.
    "kernel.dmesg_restrict"               = 1;
    # Disable unprivileged eBPF — reduces attack surface.
    "kernel.unprivileged_bpf_disabled"    = 1;
    # Restrict ptrace to direct parent processes (Yama LSM).
    "kernel.yama.ptrace_scope"            = 1;
  };

  # Blacklist unused/dangerous kernel modules. None of these protocols or bus
  # drivers are used in this homelab; preventing them from loading closes
  # known CVE classes (DCCP/RDS/TIPC have had LPE/RCE bugs).
  boot.blacklistedKernelModules = [
    "dccp"           # DCCP protocol — unused, historical CVEs
    "sctp"           # SCTP protocol — unused
    "rds"            # Reliable Datagram Sockets — unused
    "tipc"           # TIPC protocol — unused
    "firewire-core"  # FireWire — absent on VMs and server hardware
    "thunderbolt"    # Thunderbolt — absent on VMs and server hardware
  ];

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
