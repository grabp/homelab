---
kind: host
tags: [boulder, homelab, media, immich, jellyfin]
---

# boulder — Media & Productivity Server

## Role
Second homelab server. Runs media, productivity, and compute-intensive services: Immich, Jellyfin (VAAPI transcoding), Paperless-ngx, Stirling-PDF, Outline, Vikunja, Karakeep, Actual Budget, Windows VM. Accessible via NetBird mesh and via pebble's Caddy reverse proxy over LAN.

## Hardware
- **Model:** HP EliteDesk 705 G4 SFF
- **CPU:** AMD Ryzen 5 PRO 2400G (4C/8T, Vega 11 iGPU)
- **RAM:** 32 GB DDR4
- **Storage:** 250 GB SATA SSD — Samsung 840 EVO (`/dev/sda`)
- **iGPU:** AMD Vega 11 (VAAPI transcoding)
- **Network:** 1 Gbit Ethernet

## Network
- **Static IP:** `192.168.10.51` (from vars.nix)
- **Gateway:** `192.168.10.1`
- **DNS:** Pi-hole on pebble (`192.168.10.50`) + Cloudflare fallback
- **NetBird overlay IP:** Assigned by NetBird controller after login

## Disk
- **Filesystem:** ZFS
- **Pool name:** `zroot`
- **Device:** `/dev/sda` (SATA SSD)
- **Datasets:**
  - `zroot/root` — ephemeral root
  - `zroot/nix` — Nix store (persistent, never backed up)
  - `zroot/var` — service state (persistent, backed up)
  - `zroot/home` — user home directories
  - `zroot/containers` — ZFS volume with ext4 for Podman storage (100GB)
  - `zroot/reserved` — 10GB reservation (keeps pool below 80%)
- **ZFS config:** LZ4 compression, POSIX ACLs, 4K sector alignment
- **ARC cap:** 8GB (`zfs.zfs_arc_max=8589934592`)

## Secrets
- **Secrets file:** `secrets/boulder.yaml` (shared with pebble, sops-encrypted)
- **Age keys:** admin + boulder host key
- **Hostkey path:** `/etc/ssh/ssh_host_ed25519_key`
- **Status:** boulder age key not yet added — see Provisioning below

## Deploy
```bash
just deploy boulder
```
Uses IP-based deploy via deploy-rs (Pattern 18). Target IP read from `vars.nix`.

## Provisioning (First Time)

### Prerequisites
1. Physical machine connected to LAN, booted from NixOS ISO
2. Verify disk device: `lsblk -d -o NAME,SIZE,MODEL`
3. Confirm IP assignment (`192.168.10.51`) on the router

### Step 1: Generate SSH host key
```bash
just gen-boulder-hostkey
```
This generates `/tmp/boulder-hostkey/etc/ssh/ssh_host_ed25519_key` and prints the age key.

### Step 2: Add boulder to .sops.yaml
Edit `.sops.yaml`:
```yaml
keys:
  - &boulder age1...   # paste age key from step 1
```
Add `- *boulder` to the `secrets/boulder.yaml` creation rule.

### Step 3: Rekey secrets
```bash
just rekey
```
Reencrypts `secrets/boulder.yaml` so boulder can decrypt it at boot.

### Step 4: Verify the build
```bash
nix build .#nixosConfigurations.boulder.config.system.build.toplevel
```

### Step 5: Provision via nixos-anywhere
```bash
just provision-boulder 192.168.10.51
```
Runs disko (destroys disk, creates ZFS pool), installs NixOS, copies the pre-generated host key.

### Step 6: Join NetBird mesh
After first deploy, run once on boulder:
```bash
sudo netbird-wt0 up \
  --management-url https://netbird.grab-lab.gg \
  --setup-key-file /run/secrets/netbird/setup_key
```

## Verification
```bash
# SSH access
just ssh-boulder

# ZFS health
zpool status zroot

# Deploy
just deploy boulder

# NetBird
netbird-wt0 status -d
```
