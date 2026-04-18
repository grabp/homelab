# homelab/wyoming/default.nix — Wyoming voice pipeline (Stage 9b)
#
# Three native NixOS services grouped in one module because they share the
# services.wyoming.* namespace and are always deployed together:
#   - Faster-Whisper (STT): port 10300
#   - Piper (TTS):          port 10200
#   - OpenWakeWord:         port 10400
#
# HA integration (after deploy):
#   Settings → Voice assistants → create pipeline using these endpoints.
#   Each service listens on 0.0.0.0 — reachable from HA (--network=host) on localhost.
#
# ⚠ CRITICAL: ProcSubset fix for faster-whisper (nixpkgs PR #372898).
#   The systemd unit hardening sets ProcSubset=pid, blocking CTranslate2 from
#   reading /proc/cpuinfo. Without the fix, inference is ~7× slower:
#   a 3-second audio clip takes ~20 s instead of ~3 s.
{ config, lib, ... }:

let
  cfg = config.my.services.wyoming;
in
{
  options.my.services.wyoming = {
    enable = lib.mkEnableOption "Wyoming voice pipeline (Whisper STT + Piper TTS + OpenWakeWord)";
  };

  config = lib.mkIf cfg.enable {

    # === Speech-to-text (Faster-Whisper) ===
    services.wyoming.faster-whisper.servers."main" = {
      enable   = true;
      uri      = "tcp://0.0.0.0:10300";
      model    = "small-int8";   # Best latency/accuracy on Ryzen + 16 GB (~500-600 MB RAM, 2-4 s/utterance)
      language = "en";
      device   = "cpu";          # nixpkgs CTranslate2 is not compiled with CUDA; cpu is correct
    };

    # Override systemd ProcSubset hardening if it is "pid" (nixpkgs PR #372898).
    # nixos-25.11 already ships the fix (ProcSubset=all in the module), but
    # lib.mkForce is kept as explicit documentation — it is harmless when already "all".
    # Without "all", CTranslate2 cannot read /proc/cpuinfo: a 3-second clip takes ~20 s.
    systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset =
      lib.mkForce "all";

    # === Text-to-speech (Piper) ===
    services.wyoming.piper.servers."main" = {
      enable = true;
      uri    = "tcp://0.0.0.0:10200";
      voice  = "en_US-lessac-medium";   # ~65 MB, auto-downloads from HuggingFace on first use
    };

    # === Wake word detection (OpenWakeWord) ===
    # Single-instance service — no servers.<name> pattern (unlike Whisper/Piper).
    # Note: preloadModels was removed in wyoming-openwakeword v2.0.0 (Oct 2025).
    # Built-in models (okay_nabu, hey_jarvis, etc.) are loaded automatically.
    # nixos-25.11 ships v2.0.0+; no model selection option needed.
    services.wyoming.openwakeword = {
      enable = true;
      uri    = "tcp://0.0.0.0:10400";
    };

    networking.firewall.allowedTCPPorts = [ 10200 10300 10400 ];
  };
}
