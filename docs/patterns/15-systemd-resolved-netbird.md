---
kind: pattern
number: 15
tags: [systemd-resolved, netbird, pihole, DNS]
---

# Pattern 15: systemd-resolved with DNSStubListener=no (NetBird + Pi-hole coexistence)

NetBird requires `systemd-resolved` for its DNS route management — it calls `resolvectl` to register match-domain nameservers (e.g., `grab-lab.gg → Pi-hole overlay IP`). Pi-hole needs port 53. Both can coexist by disabling only the stub listener, which frees port 53 while keeping the resolved daemon running.

```nix
# In the machine config or homelab/netbird/default.nix
{
  # Pi-hole handles all DNS on port 53.
  # systemd-resolved runs as a routing daemon only — stub listener disabled.
  services.resolved = {
    enable = true;
    extraConfig = ''
      DNSStubListener=no
    '';
  };

  # Pi-hole is still responsible for /etc/resolv.conf via networking.nameservers
  # NixOS sets resolv.conf to Pi-hole's IP when DNSStubListener=no and
  # networking.nameservers is set.
  # networking.nameservers = [ "127.0.0.1" ];  # set in pebble/default.nix after Stage 3
}
```

**How it works:** With `DNSStubListener=no`, resolved does not bind `127.0.0.53:53`. Pi-hole claims port 53 on the host IP. NetBird's `resolvectl dns wt0 <pi-hole-overlay-ip>` and `resolvectl domain wt0 ~grab-lab.gg` calls succeed because resolved is still running — it just isn't serving queries itself.

**Alternative (unverified):** Set `NB_DNS_RESOLVER_ADDRESS` in the NetBird environment to move its internal resolver off port 53. Has had bugs in past versions (GitHub #2529) — the `DNSStubListener=no` approach is more reliable. ⚠️ VERIFY reliability in v0.68.x if you prefer this path.

**Source:** `services.resolved.extraConfig` verified in NixOS options ✅. `DNSStubListener=no` is a standard systemd-resolved config option ✅. Community reports confirm coexistence works with this approach.
