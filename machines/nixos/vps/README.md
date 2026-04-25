---
kind: host
tags: [vps, netbird, pocket-id]
---

# vps — NetBird Control Plane

## Role
NetBird management server and signal/coturn relay. Hosts Pocket ID (passkey-only OIDC provider for NetBird authentication). Public entry point for VPN mesh and ACME HTTP-01 challenges.

## Hardware
- **Provider:** Hetzner Cloud
- **Instance:** CX22
- **Public IP:** `204.168.181.110` (from vars.nix)
- **Virtualization:** QEMU/KVM with virtio drivers
- **Boot mode:** SeaBIOS (legacy BIOS, not UEFI)

## Network
- **Static public IP:** `204.168.181.110` (no CGNAT)
- **Firewall:** enabled
- **Allowed TCP ports:** 80 (HTTP), 443 (HTTPS), 3478 (STUN), 5349 (STUN/TLS)
- **Allowed UDP ports:** 3478 (STUN), 5349 (STUN/TLS), 49152-65535 (coturn relay range)
- **DNS:** Managed by Hetzner (DHCP)
- **NetBird overlay IP:** Assigned by NetBird controller

## Disk
- **Filesystem:** ext4 (no ZFS on VPS)
- **Device:** `/dev/sda`
- **Layout:**
  - 1M EF02 partition (BIOS boot for GRUB stage 2)
  - Remaining space: ext4 root partition

## Secrets
- **Secrets file:** `secrets/vps.yaml` (sops-encrypted)
- **Age keys:** admin + vps host key
- **Hostkey path:** `/etc/ssh/ssh_host_ed25519_key`
- **Sops format:** YAML

## Deploy
```bash
just deploy-vps
```
Uses IP-based deploy via deploy-rs (Pattern 18). Target IP read from `vars.nix`.

## Initial Provisioning
First-time setup via nixos-anywhere:
```bash
just provision-vps <IP>
```
Runs once to install NixOS on a fresh Hetzner VM. Subsequent changes use `just deploy-vps`.

## One-Time Post-Provision Steps

### 1. NetBird Server Setup
After initial deploy, the NetBird management server is running but has no users. The dashboard will show a setup prompt on first visit.

### 2. Pocket ID Initial Setup
Navigate to `https://pocket-id.grab-lab.gg/login/setup` (NOT `/setup` — that path doesn't exist in v1.3.1). Create the first admin user with a passkey.

**After setup:**
- Configure OIDC client in Pocket ID for NetBird:
  - Client ID: from NetBird dashboard OIDC settings
  - Redirect URI: `https://netbird.grab-lab.gg/auth`
  - **Client type:** Public (NOT confidential — NetBird SPA can't send client_secret)
  - **Scopes:** `openid profile email groups` (no `offline_access` — unsupported)
- Lock signups: `ALLOW_USER_SIGNUPS=disabled` (already set in module)

### 3. Approve New Users in NetBird
After switching IdPs, new users synced from Pocket ID are created with `blocked=1` and `pending_approval=1`. Approve before first login:
```bash
sudo sqlite3 /var/lib/netbird-mgmt/store.db \
  "UPDATE users SET blocked=0, pending_approval=0, role='owner' \
   WHERE id='<pocket-id-user-uuid>';"
```
No container restart needed — management server reads SQLite live.

## Verification
```bash
# Container status
podman ps  # netbird-management, netbird-dashboard, pocket-id

# NetBird peer status (VPS as client)
netbird-wt0 status -d

# Service endpoints
curl -I https://netbird.grab-lab.gg  # NetBird dashboard
curl -I https://pocket-id.grab-lab.gg  # Pocket ID login page
```
