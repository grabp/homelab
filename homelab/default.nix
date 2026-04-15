# homelab/default.nix — service modules (enabled per-machine in machines/nixos/<host>/default.nix)
# Each service uses mkEnableOption — disabled by default, opt-in per machine.
#
# Services are imported here as stages progress:
#   Stage 3: pihole
#   Stage 4: caddy
#   Stage 5: vaultwarden
#   Stage 6: prometheus, grafana, loki
#   Stage 7: netbird
#   Stage 8: homepage
#   Stage 9: home-assistant, uptime-kuma
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
    # ./homepage
    # ./home-assistant
    # ./uptime-kuma
    # ./backup
  ];
}
