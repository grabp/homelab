---
kind: roadmap
stage: 18
title: Whisper Migration
status: not-started
---

# Stage 18: Whisper Migration — Move STT from Pebble to Boulder

## Status
NOT STARTED

## What Gets Built
Wyoming Faster-Whisper service on boulder (same config as pebble), Home Assistant on pebble reconfigured to use boulder's Whisper endpoint.

## Key Files
- Add Wyoming config to boulder
- Update HA configuration on pebble

## Dependencies
- Stage 11 (boulder running)
- Stage 9b complete on pebble (voice pipeline tested)

## Verification Steps
- [ ] Wyoming Whisper running on boulder:10300
- [ ] Home Assistant voice assistant uses `boulder.lan:10300` for STT
- [ ] Voice commands work with new endpoint
- [ ] Pebble's Whisper service disabled
- [ ] Pebble RAM usage reduced by ~500–800 MB

## Estimated Complexity
Low. Config migration only.
