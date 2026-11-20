---
service: wyoming
stage: 9b
machine: pebble
status: deployed
---

# Wyoming Voice Pipeline

## Purpose

Local voice assistant pipeline for Home Assistant. Three native NixOS services:

- **Faster-Whisper** — speech-to-text (STT) using the `small-int8` model
- **Piper** — text-to-speech (TTS) with `en_US-lessac-medium` voice
- **OpenWakeWord** — wake word detection (currently no preloaded model)

All three listen on localhost; HA connects via the Wyoming integration.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 10300 | TCP | localhost | Faster-Whisper STT (Wyoming protocol) |
| 10200 | TCP | localhost | Piper TTS (Wyoming protocol) |
| 10400 | TCP | localhost | OpenWakeWord wake word detection |

## Secrets

None.

## Depends on

- Home Assistant (HA connects to these ports; these services don't depend on HA)

## DNS

Not exposed via Caddy — HA connects directly over localhost.

## OIDC

Not applicable.

## Known gotchas

- **ProcSubset performance bug (nixpkgs PR #372898):** systemd hardening sets
  `ProcSubset=pid`, blocking faster-whisper from reading `/proc/cpuinfo`.
  CTranslate2 falls back to a slow path — 3s audio takes ~20s instead of ~3s.
  **Always apply the workaround:**
  ```nix
  systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset = lib.mkForce "all";
  ```
  This is already applied in the module.
- **Fails at boot if huggingface.co is unreachable:** faster-whisper fetches the
  `openai/whisper-tiny` tokenizer on every start (`HF_HOME=/tmp`). A failed
  request surfaces as `RuntimeError: Cannot send a request, as the client has
  been closed` (huggingface_hub 1.x masks the real error — look for
  `thrown while requesting` lines). The module sets `Restart = "on-failure"`.
  If it keeps failing, check `getent hosts huggingface.co` on pebble — Pi-hole
  may be serving a cached upstream block (`0.0.0.0`); `pihole reloaddns` clears it.
- `device = "cpu"` is required — `pkgs.wyoming-faster-whisper` is not compiled
  with CUDA support.
- OpenWakeWord v2.0.0 renamed `ok_nabu` → `okay_nabu`. Verify model name
  matches the nixpkgs channel version.
- Piper voice models auto-download from HuggingFace on first start (~65 MB for
  `en_US-lessac-medium`); internet access required on first deploy.

## Backup / restore

State:
- `/var/lib/private/wyoming-faster-whisper/` — downloaded models (~500 MB for `small-int8`)
- `/var/lib/private/wyoming-piper/` — downloaded voice models

Models are re-downloaded automatically on first start after restore. No
persistent user data.
