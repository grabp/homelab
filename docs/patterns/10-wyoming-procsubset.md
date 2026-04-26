---
kind: pattern
number: 10
tags: [wyoming, home-assistant, systemd, hardening]
---

# Pattern 10: Native Wyoming service with systemd ProcSubset override

The `wyoming-faster-whisper` NixOS module applies systemd hardening with `ProcSubset=pid`, which blocks CTranslate2 from reading `/proc/cpuinfo`. This forces a slow fallback code path — inference is ~7× slower. Always override with `lib.mkForce`. Same pattern applies if other Wyoming services ever exhibit similar hardening issues.

```nix
# homelab/wyoming/default.nix
{ config, lib, pkgs, vars, ... }:

{
  # === Speech-to-text (Faster-Whisper) ===
  services.wyoming.faster-whisper.servers."main" = {
    enable = true;
    uri = "tcp://0.0.0.0:10300";
    model = "small-int8";   # Best latency/accuracy on Ryzen + 16 GB
    language = "en";
    device = "cpu";         # CUDA not available in nixpkgs CTranslate2
  };

  # CRITICAL: Override systemd ProcSubset hardening (nixpkgs PR #372898)
  # Without this, CTranslate2 cannot read /proc/cpuinfo and falls back
  # to a slow code path — a 3-second clip takes ~20 s instead of ~3 s.
  systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset =
    lib.mkForce "all";

  # === Text-to-speech (Piper) ===
  services.wyoming.piper.servers."main" = {
    enable = true;
    uri = "tcp://0.0.0.0:10200";
    voice = "en_US-lessac-medium";   # ~65 MB, auto-downloads from HuggingFace
  };

  # === Wake word detection (OpenWakeWord) — single instance, no servers.<name> ===
  # ⚠️ `preloadModels` was REMOVED in wyoming-openwakeword v2.0.0 (Oct 2025).
  # nixos-25.11 ships v2.0.0+. Built-in models load automatically.
  # Do NOT set preloadModels — the option no longer exists and causes an eval error.
  services.wyoming.openwakeword = {
    enable = true;
    uri    = "tcp://0.0.0.0:10400";
    # Built-in models (okay_nabu, hey_jarvis, alexa, hey_mycroft, hey_rhasspy) auto-load.
    # Add custom models via customModelsDirectories = [ /path/to/models ];
  };

  networking.firewall.allowedTCPPorts = [ 10200 10300 10400 ];
}
```

**Source:** NixOS module source at `nixos/modules/services/home-automation/wyoming/`. ProcSubset bug confirmed in nixpkgs PR #372898 — merged into nixos-25.11 (`ProcSubset = "all"` already in module). `lib.mkForce "all"` override harmless and kept for explicit documentation. `preloadModels` removal verified against nixos-25.11 rev `7e495b747b51` ✅.
