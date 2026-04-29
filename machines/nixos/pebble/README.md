---
kind: host
tags: [pebble, homelab]
---

# pebble — Homelab Server

## Role
Primary service host for the homelab. Runs all core services (Pi-hole, Caddy, Grafana, Loki, Kanidm, Home Assistant, etc.) and acts as a NetBird routing peer to expose LAN services over the mesh VPN.

## Hardware
- **Model:** HP ProDesk (AMD CPU, see hardware.nix)
- **Platform:** x86_64-linux
- **RAM:** 16GB (4GB allocated to ZFS ARC, ~12GB for services)
- **CPU:** AMD (KVM virtualization support)

## Network
- **Static IP:** `192.168.10.50` (from vars.nix)
- **Gateway:** `192.168.10.1`
- **Interface:** eth0 (name derived from hardware scan)
- **DNS:** Pi-hole (127.0.0.1) + Cloudflare (1.1.1.1 fallback)
- **NetBird overlay IP:** Assigned by NetBird controller after login
- **Constraints:** Behind CGNAT — no public IP, inbound access via NetBird mesh

## Disk
- **Filesystem:** ZFS
- **Pool name:** `zroot`
- **Device:** `/dev/nvme0n1` (NVMe SSD)
- **Datasets:**
  - `zroot/root` — ephemeral (optional rollback to `@blank` snapshot)
  - `zroot/nix` — Nix store (large, persistent, never backed up)
  - `zroot/var` — service state (persistent, backed up via Restic)
  - `zroot/home` — user home directories
  - `zroot/containers` — ZFS volume with ext4 for Podman storage (50GB)
  - `zroot/reserved` — 10GB reservation to keep pool below 80% threshold
- **ZFS config:** LZ4 compression, POSIX ACLs, 4K sector alignment
- **ARC cap:** 4GB (via `zfs.zfs_arc_max` kernel param)

## Secrets
- **Secrets file:** `secrets/pebble.yaml` (sops-encrypted)
- **Age keys:** admin + pebble host key
- **Hostkey path:** `/etc/ssh/ssh_host_ed25519_key`
- **Sops format:** YAML

## Deploy
```bash
just deploy pebble
```
Uses IP-based deploy via deploy-rs (Pattern 18). Target IP read from `vars.nix`.

## Provisioning (First Time)

### Prerequisites
1. Physical machine connected to LAN
2. Verify disk device: `lsblk -d -o NAME,SIZE,MODEL,TRAN` — expected `/dev/nvme0n1`
3. Static IP `192.168.10.50` reserved on the router
4. Boot mode: **UEFI** (HP ProDesk supports UEFI — systemd-boot is used)

### Step 1: Generate SSH host key
```bash
just gen-pebble-hostkey
```
Prints the age public key needed for `.sops.yaml`.

### Step 2: Add pebble to `.sops.yaml`
```yaml
keys:
  - &pebble age1...   # paste age key from step 1
```
Add `- *pebble` to the `secrets/pebble.yaml` creation rule.

### Step 3: Create secrets and rekey
```bash
just edit-secrets-pebble   # add all pebble secrets
just rekey
```

### Step 4: Verify the build
```bash
nix build .#nixosConfigurations.pebble.config.system.build.toplevel
```

### Step 5: Provision via nixos-anywhere
```bash
just provision-pebble 192.168.10.50
```
nixos-anywhere kexecs a NixOS installer, runs disko (destroys disk, creates ZFS pool), installs NixOS, uploads the pre-generated host key.

> **If kexec causes a power-off** (can happen on HP bare metal): boot a NixOS minimal ISO from USB instead, then re-run `just provision-pebble 192.168.10.50`. nixos-anywhere detects the live environment and skips kexec.
>
> **If disko fails with "bogus FAT filesystem"**: re-run — this is a one-time partition table rescan race condition. Second run succeeds.

### Step 6: Join NetBird mesh
```bash
sudo netbird-wt0 up \
  --management-url https://netbird.grab-lab.gg \
  --setup-key-file /run/secrets/netbird/setup_key
```
Credentials persist in `/var/lib/netbird-wt0/` across reboots. No need to re-run after restarts.

## Verification
```bash
# NetBird connection
netbird-wt0 status -d  # peers Connected, WireGuard handshake established

# ZFS health
zpool status zroot

# Service status
systemctl status netbird-wt0 systemd-resolved pihole caddy grafana
```
