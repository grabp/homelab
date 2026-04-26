---
kind: roadmap
stage: 14
title: Immich Photo Management
status: not-started
---

# Stage 14: Immich Photo Management

## Status
NOT STARTED

## What Gets Built
Immich server (Podman containers: server, machine-learning, Redis) with PostgreSQL backend, NAS storage for photos, ML-based face/object recognition.

## Key Files
- Container configs in boulder's default.nix or dedicated `homelab/immich/default.nix`

## Dependencies
- Stage 12 (PostgreSQL)
- NAS mount for `/mnt/nas/photos`

## Verification Steps
- [ ] `https://immich.grab-lab.gg` loads Immich web UI
- [ ] Photo upload works
- [ ] Face recognition processes photos
- [ ] Mobile app connects and syncs

## Estimated Complexity
Medium-high. Multi-container orchestration, ML inference can be resource-intensive.
