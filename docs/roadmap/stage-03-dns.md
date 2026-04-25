---
kind: roadmap
stage: 3
title: DNS with Pi-hole
status: complete
---

# Stage 3: DNS (Pi-hole)

## Status
COMPLETE (implemented 2026-04-12)

## Files Created
- `modules/podman/default.nix` — Podman base config, OCI backend
- `homelab/pihole/default.nix` — Pi-hole module: OCI container, port 53 + 8089, wildcard split DNS

## Files Modified
- `flake.nix` — added `./modules/podman` to pebble modules
- `homelab/default.nix` — enabled `./pihole` import
- `machines/nixos/pebble/default.nix` — `my.services.pihole.enable = true`

## Configuration Notes
- Image: `pihole/pihole:2025.02.1` (Pi-hole v6)
- Web UI: port 8089 (mapped from container port 80)
- Split DNS: `address=/grab-lab.gg/192.168.10.50` written to `/var/lib/pihole-dnsmasq/04-grab-lab.conf` via `system.activationScripts`; `FTLCONF_misc_etc_dnsmasq_d=true` enables reading `/etc/dnsmasq.d/` (off by default in v6)
- `FTLCONF_misc_dnsmasq_lines` is unusable for `address=` directives — Pi-hole v6 splits array items on `=`, discarding everything after the first `=`
- Conditional forwarding (.lan/.local → router): `server=/domain/ip` in dnsmasq conf-dir files is a known Pi-hole v6 bug (#6279, returns 0ms NXDOMAIN without forwarding); use `FTLCONF_dns_revServers` instead — format: `"true,CIDR,server#port,domain"`, semicolon-separated for multiple domains
- Secret: `pihole/env` in `secrets/secrets.yaml` must contain `FTLCONF_webserver_api_password=<password>`
- `services.resolved.enable = false` — Stage 6b (NetBird) re-enables it with `DNSStubListener=no`
- **Volume directory ownership:** Pi-hole's FTL process drops from root to UID 1000 (`pihole` user) after binding port 53. SQLite WAL mode needs write access to the directory (not just the `.db` file) to create `.db-wal`/`.db-shm` lock files. `systemd.tmpfiles.rules` `d` type defaults to `root root`, causing "attempt to write a readonly database" when editing domain lists. Fixed by setting `"d /var/lib/pihole 0755 1000 1000 -"` and running `sudo chown 1000:1000 /var/lib/pihole` on the already-existing directory. See docs/NIX-PATTERNS.md Pattern 17.
- **Netavark/firewall ordering bug:** when `nixos-rebuild switch` reloads `firewall.service` (any change to `networking.firewall.*`), NixOS flushes all iptables chains including `NETAVARK_*`. If the Pi-hole container isn't restarted, its DNAT rules for port 53 are gone and external DNS queries time out. Fixed via `systemd.services.podman-pihole = { after = ["firewall.service"]; partOf = ["firewall.service"]; }` — applies to ALL future OCI containers that publish ports.
- `deploy.nodes.*.hostname` must be the actual IP/FQDN — fixed via `deployHostname` in `flakeHelpers.nix`
- `nix.settings.trusted-users = ["root" "admin"]` required for deploy-rs to push store paths

## Pre-Deploy Action Required
```bash
just edit-secrets  # add: pihole/env: "FTLCONF_webserver_api_password=<your-password>"
```

## Verification (All Passed)
- [x] `podman ps` shows pihole container running
- [x] `dig @192.168.10.50 google.com` returns results (upstream DNS works)
- [x] `dig @192.168.10.50 grafana.grab-lab.gg` returns `192.168.10.50` (split DNS works)
- [x] Pi-hole admin UI at `http://192.168.10.50:8089/admin` loads
- [x] Set UniFi DHCP DNS to `192.168.10.50`; verify clients resolve via Pi-hole
- [x] `dig @192.168.10.50 unifi.lan` returns router answer (conditional forwarding works)
