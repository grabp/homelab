---
kind: roadmap
stage: 11
title: Boulder Base System
status: not-started
---

# Stage 11: Base System — Boulder Hardware Provisioning

## Status
NOT STARTED

## What Gets Built
NixOS on boulder via disko (ZFS), SSH access, add to flake as second machine, node_exporter + promtail for monitoring, NetBird client for VPN access.

## Key Files
- `machines/nixos/boulder/{default,disko,hardware}.nix`
- Update `flake.nix` with `mkNixos "boulder"`

## Dependencies
- Complete all Phase 1 stages (1–10) on pebble
- Physical hardware ready
- Static IP assigned (192.168.10.51)
- SSH key in place

## Verification Steps
- [ ] `ssh admin@192.168.10.51` works
- [ ] `zpool status` shows healthy pool
- [ ] `just deploy boulder` deploys successfully
- [ ] Prometheus targets show boulder's node_exporter as UP
- [ ] Loki receives logs from boulder's promtail
- [ ] `netbird-wt0 status` shows connected to control plane

## Estimated Complexity
Low-medium. Same process as pebble Stage 1, but second time is faster.
