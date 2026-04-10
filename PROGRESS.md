# Implementation Progress

## Current Stage: 2 — Secrets Management
## Status: NOT STARTED

---

## Stage 1: Base System — COMPLETE

**Files created:**
- `flake.nix` — inputs: nixpkgs 25.11, deploy-rs, disko, sops-nix
- `flakeHelpers.nix` — `mkNixos` + `mkMerge` helpers
- `machines/nixos/vars.nix` — domain, serverIP, timezone, etc.
- `machines/nixos/_common/` — nix-settings, ssh, users, locale
- `machines/nixos/elitedesk/default.nix` — ZFS boot, static IP, firewall
- `machines/nixos/elitedesk/disko.nix` — ZFS pool (zroot) with ESP
- `machines/nixos/elitedesk/hardware.nix` — placeholder (replace on install)
- `homelab/default.nix` — stub for future service modules
- `modules/networking/default.nix` — `my.networking.staticIPv4` custom module
- `users/admin/default.nix` — admin user, passwordless sudo
- `justfile` — build, switch, deploy, secrets, gen-hostid

**Before first deployment (manual steps required):**
1. Generate hostId: `just gen-hostid` → update `machines/nixos/elitedesk/default.nix`
2. Verify disk path (`/dev/sda` or `/dev/nvme0n1`): update `machines/nixos/elitedesk/disko.nix`
3. Add SSH public key to `users/admin/default.nix`
4. After partitioning, replace `hardware.nix` with `nixos-generate-config --show-hardware-config` output
5. After Stage 3 (Pi-hole), change `nameservers` in `elitedesk/default.nix` to `[ "127.0.0.1" ]`
6. Add `networking.interfaces.<actual-iface>` — verify interface name with `ip link`

**Verification steps (from STAGES.md):**
- [ ] Boot into NixOS from SSD
- [ ] `zpool status` shows healthy pool with compression enabled
- [ ] SSH login works with key-based auth
- [ ] `ip addr` shows static IP `192.168.10.50/24`
- [ ] `curl https://nixos.org` works (internet connectivity)
- [ ] `nixos-rebuild switch --flake .` succeeds locally

---

## Stage 2: Secrets Management — NOT STARTED

**Prerequisites:** SSH host key on deployed machine (for age key derivation)

**What to do:**
1. Deploy Stage 1 first (get SSH host key)
2. `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub` (on server) → get server age key
3. `age-keygen` (on dev machine) → get admin age key
4. Create `.sops.yaml` with both keys
5. `sops secrets/secrets.yaml` to create initial test secret
6. Add sops module config to `machines/nixos/elitedesk/default.nix`

---

## Stage 3: DNS (Pi-hole) — NOT STARTED
## Stage 4: Reverse Proxy (Caddy) — NOT STARTED
## Stage 5: Monitoring (Prometheus + Grafana + Loki) — NOT STARTED
## Stage 6: VPN (NetBird) — NOT STARTED
## Stage 7: Homepage Dashboard — NOT STARTED
## Stage 8: Services (Home Assistant + Uptime Kuma) — NOT STARTED
## Stage 9: Hardening, Backups, deploy-rs — NOT STARTED
