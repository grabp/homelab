---
kind: pattern
number: 18
tags: [ssh, deployment, DNS, safety]
---

# Pattern 18: Always use IP addresses for SSH, never domain names

**Problem:** When deploying to multiple machines, DNS resolution can return the wrong IP if Pi-hole or split-horizon DNS is misconfigured. A command like `ssh admin@netbird.grab-lab.gg` may resolve to a LAN server (192.168.10.50) instead of the intended VPS (204.168.181.110), causing the wrong machine to receive the deployment — potentially breaking the local server with incompatible configuration.

**Rule:** Always use explicit IP addresses from `vars.nix` for SSH and deployment commands. Never rely on domain names for infrastructure operations.

```nix
# machines/nixos/vars.nix — single source of truth for IPs
{
  serverIP = "192.168.10.50";   # pebble (homelab)
  vpsIP = "204.168.181.110";    # VPS (NetBird control plane)
  routerIP = "192.168.1.1";
}
```

```just
# justfile — use IPs, not domains
ssh-pebble:
    ssh admin@192.168.10.50

ssh-vps:
    ssh admin@204.168.181.110

deploy-vps:
    # deploy-rs uses hostname from flakeHelpers.nix — ensure it's the IP, not domain
    nix run github:serokell/deploy-rs -- -s .#vps
```

```nix
# flakeHelpers.nix — deploy.nodes hostname must be IP for VPS
deploy.nodes.${hostname} = {
  hostname = deployHostname hostname;  # Returns IP from vars.nix, not domain
  # ...
};
```

**Recovery if wrong machine was deployed:**
1. Physical access: reboot, select previous NixOS generation from GRUB menu
2. Boot into working generation
3. Run `sudo /run/current-system/bin/switch-to-configuration boot` to make it default

**Source:** Discovered during Stage 7a when `ssh admin@netbird.grab-lab.gg` resolved to pebble (192.168.10.50) instead of VPS, deploying VPS config to the homelab server and breaking SSH access. Required physical console recovery ✅.
