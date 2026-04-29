---
kind: roadmap
stage: 11
title: Boulder Base System
status: complete
---

# Stage 11: Base System — Boulder Hardware Provisioning

## Status
COMPLETE (2026-04-29)

## What Gets Built
NixOS on boulder (HP EliteDesk 705 G4) via disko (ZFS), SSH access, added to flake as third machine, NetBird client for VPN access. Monitoring via shared homelab modules (`my.services.nodeExporter`, `my.services.alloy`). Foundation for all Phase 2 services.

Also extracted and generalised during this stage: `homelab/alloy` (shared Alloy log shipper), `homelab/node-exporter` (shared node_exporter), and `homelab/pocket-id` (moved from `vps/pocket-id.nix`). Prometheus and Loki modules refactored to use these shared modules.

## Files Created
- `machines/nixos/boulder/disko.nix` — ZFS disk layout for SATA SSD `/dev/sda` (GPT + EF00 ESP + ZFS partition)
- `machines/nixos/boulder/hardware.nix` — AMD Ryzen 5 PRO 2400G, SATA kernel modules (no NVMe)
- `machines/nixos/boulder/default.nix` — base config: ZFS boot, static IP, firewall, sops, netbird, alloy, node-exporter
- `machines/nixos/boulder/README.md` — machine documentation and provisioning guide
- `homelab/alloy/default.nix` — shared Alloy log shipper module (`my.services.alloy`, configurable `hostLabel` + `lokiUrl`)
- `homelab/alloy/README.md`
- `homelab/node-exporter/default.nix` — shared node_exporter module (`my.services.nodeExporter`, configurable `openFirewall`)
- `homelab/node-exporter/README.md`
- `homelab/pocket-id/default.nix` — moved from `machines/nixos/vps/pocket-id.nix`
- `homelab/pocket-id/README.md`

## Files Modified
- `flake.nix` — added `mkNixos "boulder"`; added `./homelab/alloy` and `./homelab/pocket-id` to VPS modules
- `flakeHelpers.nix` — `deployHostname` returns `vars.boulderIP` for boulder (Pattern 18)
- `machines/nixos/vars.nix` — added `boulderIP = "192.168.10.51"`; renamed `serverIP` → `pebbleIP`
- `.sops.yaml` — added boulder age key; added `secrets/boulder.yaml` creation rule
- `justfile` — added `gen-boulder-hostkey`, `provision-boulder`, `ssh-boulder`, `edit-secrets-boulder`
- `homelab/loki/default.nix` — replaced inline Alloy config with `my.services.alloy`
- `homelab/prometheus/default.nix` — replaced inline `exporters.node` with `my.services.nodeExporter`
- `machines/nixos/pebble/default.nix` — added boulder Prometheus scrape target; opened Loki port on `eth0`
- `machines/nixos/vps/default.nix` — replaced `./monitoring.nix` import with `my.services.alloy`; removed `./pocket-id.nix` import

## Dependencies
- Phase 1 complete (stages 1–10b on pebble) ✅
- Physical hardware connected to LAN
- Static IP `192.168.10.51` reserved on router
- SSH key from `users/admin` already in flake

## Provisioning Workflow

### Pre-provisioning (run from dev machine)

**1. Generate SSH host key**
```bash
just gen-boulder-hostkey
```
Outputs the age public key (e.g. `age1...`). This solves the sops chicken-and-egg problem — the key must exist before secrets can be encrypted for boulder.

**2. Add boulder to `.sops.yaml`**
Uncomment and populate the boulder lines:
```yaml
keys:
  - &boulder age1...   # paste output from gen-boulder-hostkey
```
Add `- *boulder` to the `secrets/boulder.yaml` creation rule.

**3. Rekey secrets**
```bash
just rekey
```
Reencrypts `secrets/boulder.yaml` with boulder's age key so sops-nix can decrypt at boot.

**4. Verify the build**
```bash
nix build .#nixosConfigurations.boulder.config.system.build.toplevel
```

**5. Provision via nixos-anywhere**
```bash
just provision-boulder 192.168.10.51
```
Runs disko (destroys disk, partitions GPT, creates ZFS pool `zroot`), installs NixOS, uploads the pre-generated SSH host key via `--extra-files`.

### Post-provisioning (run on boulder via SSH)

**6. Verify SSH access**
```bash
just ssh-boulder
```

**7. Join NetBird mesh**
```bash
sudo netbird-wt0 up \
  --management-url https://netbird.grab-lab.gg \
  --setup-key-file /run/secrets/netbird/setup_key
```
Credentials persist in `/var/lib/netbird-wt0/` across reboots — no need to re-run after restarts.

**8. Approve peer in NetBird dashboard**
New peers may require approval at `https://netbird.grab-lab.gg`. If the setup key is reusable (created in Stage 7a), approval is automatic.

## Configuration Notes
- `networking.hostId = "72b51f0c"` — pre-generated; unique from pebble (`8423e349`)
- `networking.hostName = "boulder"`
- Static IP `192.168.10.51` via `my.networking.staticIPv4` module
- DNS: Pi-hole on pebble (`192.168.10.50`) as primary, Cloudflare fallback
- ARC cap: 8GB (`zfs.zfs_arc_max=8589934592`) — 32GB total RAM
- Containers volume: 100GB ZFS volume with ext4 (vs 50GB on pebble — larger for Immich/Jellyfin layers)
- UEFI boot via systemd-boot (HP EliteDesk 705 G4 supports UEFI)
- `secrets/boulder.yaml` is boulder-only (own age key). Contains `netbird/setup_key` (same value as pebble's, but separate encrypted copy)
- Monitoring: node_exporter scraped by pebble Prometheus over LAN (`192.168.10.51:9100`, `job_name = "node_boulder"`); Alloy ships logs to pebble Loki over LAN (`192.168.10.50:3100`) — no NetBird hop needed
- Hardware: Samsung SSD 840 EVO 250 GB SATA at `/dev/sda` (not NVMe)

## Verification Steps
- [x] `just gen-boulder-hostkey` — key generated, age key noted
- [x] `.sops.yaml` updated with boulder age key
- [x] `secrets/boulder.yaml` created with `netbird/setup_key`
- [x] `nix build .#nixosConfigurations.boulder.config.system.build.toplevel` — builds cleanly
- [x] `just provision-boulder 192.168.10.51` — provisioning succeeds
- [x] `just ssh-boulder` — SSH as admin works
- [x] `zpool status zroot` on boulder — ONLINE, no errors
- [x] `systemctl --failed` — 0 units
- [x] `just deploy boulder` — deploy-rs deploy succeeds
- [x] `netbird-wt0 status -d` on boulder — connected to control plane
- [x] Prometheus targets show boulder node_exporter as UP (`192.168.10.51:9100`)
- [x] Loki receives logs from boulder (`{host="boulder"}` in Grafana)

## Next Stage
Stage 12: PostgreSQL shared instance for Outline, Vikunja, Paperless-ngx.
