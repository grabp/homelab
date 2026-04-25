---
kind: roadmap
stage: 15
title: Jellyfin Media Server
status: not-started
---

# Stage 15: Jellyfin Media Server

## Status
NOT STARTED

## What Gets Built
Jellyfin media server (native module preferred, container as fallback) with VAAPI hardware transcoding, NAS storage for media library.

## Key Files
- `homelab/jellyfin/default.nix`

## Dependencies
- Stage 11 (GPU access configured)
- NAS mount for `/mnt/nas/media`

## Verification Steps
- [ ] `https://jellyfin.grab-lab.gg` loads Jellyfin web UI
- [ ] Media library scanned from NAS
- [ ] Playback works (direct play and transcoding)
- [ ] VAAPI transcoding active (check Jellyfin dashboard)
- [ ] DLNA discovery works on LAN

## Estimated Complexity
Medium. VAAPI configuration requires GPU permissions.
