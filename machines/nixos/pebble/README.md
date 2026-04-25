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
- **Secrets file:** `secrets/secrets.yaml` (sops-encrypted)
- **Age keys:** admin + pebble host key
- **Hostkey path:** `/etc/ssh/ssh_host_ed25519_key`
- **Sops format:** YAML

## Deploy
```bash
just deploy pebble
```
Uses IP-based deploy via deploy-rs (Pattern 18). Target IP read from `vars.nix`.

## One-Time Post-Provision Steps
After initial provisioning and deploy, run the NetBird login command once to join the mesh VPN:
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
