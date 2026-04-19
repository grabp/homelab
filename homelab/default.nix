# homelab/default.nix — service modules (enabled per-machine in machines/nixos/<host>/default.nix)
# Each service uses mkEnableOption — disabled by default, opt-in per machine.
#
# Services are imported here as stages progress:
#   Stage 3: pihole
#   Stage 4: caddy
#   Stage 5: vaultwarden
#   Stage 6: prometheus, grafana, loki
#   Stage 7b: netbird
#   Stage 7c: kanidm
#   Stage 8: homepage
#   Stage 9a: mosquitto, home-assistant (+ ESPHome), uptime-kuma
#   Stage 9b: wyoming, matter-server
#   Stage 10: backup
{ ... }: {
  imports = [
    # Uncomment as each stage is implemented:
    ./pihole          # Stage 3
    ./caddy           # Stage 4
    ./vaultwarden     # Stage 5
    ./prometheus       # Stage 6
    ./grafana          # Stage 6
    ./loki             # Stage 6
    ./netbird          # Stage 7b
    ./kanidm           # Stage 7c — Kanidm OIDC + LDAP IdP
    ./homepage         # Stage 8
    ./mosquitto        # Stage 9a
    ./home-assistant   # Stage 9a — includes ESPHome container (9b sub-option)
    ./uptime-kuma      # Stage 9a
    ./wyoming          # Stage 9b — Whisper STT + Piper TTS + OpenWakeWord
    ./matter-server    # Stage 9b — Matter Server OCI container
    ./backup           # Stage 10 — Sanoid + Syncoid + Restic
  ];
}
