# homelab/default.nix — service modules (enabled per-machine in machines/nixos/<host>/default.nix)
# Each service uses mkEnableOption — disabled by default, opt-in per machine.
#
# Services are imported here as stages progress:
#   Stage 3: pihole
#   Stage 4: caddy
#   Stage 5: prometheus, grafana, loki
#   Stage 6: netbird
#   Stage 7: homepage
#   Stage 8: home-assistant, uptime-kuma
#   Stage 9: backup
{ ... }: {
  imports = [
    # Uncomment as each stage is implemented:
    ./pihole          # Stage 3
    ./caddy           # Stage 4
    # ./prometheus
    # ./grafana
    # ./loki
    # ./netbird
    # ./homepage
    # ./home-assistant
    # ./uptime-kuma
    # ./backup
  ];
}
