# Implementation Progress

## Current Stage: 2 — Secrets Management
## Status: NOT STARTED

---

## Stage 1: Base System — COMPLETE (verified 2026-04-11)

**Files created:**
- `flake.nix` — inputs: nixpkgs 25.11, deploy-rs, disko, sops-nix
- `flakeHelpers.nix` — `mkNixos` + `mkMerge` helpers
- `machines/nixos/vars.nix` — domain, serverIP, timezone, etc.
- `machines/nixos/_common/` — nix-settings, ssh, users, locale
- `machines/nixos/pebble/default.nix` — ZFS boot, static IP, firewall
- `machines/nixos/pebble/disko.nix` — ZFS pool (zroot) on `/dev/nvme0n1`
- `machines/nixos/pebble/hardware.nix` — generated for HP ProDesk
- `homelab/default.nix` — stub for future service modules
- `modules/networking/default.nix` — `my.networking.staticIPv4` custom module
- `users/admin/default.nix` — admin user with SSH key, passwordless sudo
- `justfile` — build, switch, deploy, secrets, gen-hostid

**Configuration notes:**
- `networking.hostId = "8423e349"` — generated during disko partitioning
- `boot.zfs.forceImportRoot = true` — required for ZFS import during boot
- Network interface: `eth0` (matches module default)

**Verification (all passed):**
- [x] Boot into NixOS from SSD
- [x] `zpool status` shows healthy pool with compression enabled
- [x] SSH login works with key-based auth
- [x] `ip addr` shows static IP `192.168.10.50/24`
- [x] `curl https://nixos.org` works (internet connectivity)
- [x] `nixos-rebuild switch --flake .` succeeds locally

---

## Stage 2: Secrets Management — NOT STARTED

**Prerequisites:** SSH host key on deployed machine (for age key derivation)

**What to do:**
1. Deploy Stage 1 first (get SSH host key)
2. `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub` (on server) → get server age key
3. `age-keygen` (on dev machine) → get admin age key
4. Create `.sops.yaml` with both keys
5. `sops secrets/secrets.yaml` to create initial test secret
6. Add sops module config to `machines/nixos/pebble/default.nix`

---

## Stage 3: DNS (Pi-hole) — NOT STARTED
## Stage 4: Reverse Proxy (Caddy) — NOT STARTED
## Stage 5: Monitoring (Prometheus + Grafana + Loki) — NOT STARTED
## Stage 6: VPN (NetBird) — NOT STARTED
## Stage 7: Homepage Dashboard — NOT STARTED
## Stage 8: Services (Home Assistant + Uptime Kuma) — NOT STARTED
## Stage 9: Hardening, Backups, deploy-rs — NOT STARTED
