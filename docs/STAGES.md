# STAGES.md — Staged Implementation Plan

Each stage is independently deployable and testable. Complete each stage before proceeding.

## Stage 1: Base system — disko, boot, SSH, user, networking

**What gets built:** Bootable NixOS on ZFS via disko, SSH access, admin user with sudo, static IP on 192.168.10.0/24, basic firewall, flake structure with `flakeHelpers.nix`.

**Key files:** `flake.nix`, `flakeHelpers.nix`, `machines/nixos/pebble/{default,disko,hardware}.nix`, `machines/nixos/_common/`, `users/admin/`, `machines/nixos/vars.nix`

**Dependencies:** NixOS installer ISO, network connectivity, target disk identified (`/dev/sda` or `/dev/nvme0n1`).

**Verification steps:**
- Boot into NixOS from SSD
- `zpool status` shows healthy pool with compression enabled
- SSH login works with key-based auth
- `ip addr` shows static IP `192.168.10.X/24`
- `curl https://nixos.org` works (internet connectivity)
- `nixos-rebuild switch --flake .` succeeds locally

**Estimated complexity:** Medium. Disk partitioning with disko requires careful device path identification. ZFS hostId must be generated.

## Stage 2: Secrets management — sops-nix + age

**What gets built:** sops-nix integrated into flake, `.sops.yaml` configured, initial secrets file with a test secret, age key derived from SSH host key.

**Key files:** `secrets/secrets.yaml`, `.sops.yaml`, sops-nix module added to `flake.nix`

**Dependencies:** Stage 1 (SSH host key exists for age key derivation). Install `sops` and `age` on your development machine.

**Verification steps:**
- `sops secrets/secrets.yaml` opens editor and encrypts on save
- `nixos-rebuild switch` decrypts secrets successfully
- `cat /run/secrets/test_secret` shows decrypted value
- Secret file permissions are `0400` with correct owner

**Estimated complexity:** Low-medium. Initial setup of `.sops.yaml` and key derivation is a one-time learning curve.

## Stage 3: DNS — Pi-hole via Podman

**What gets built:** Pi-hole running as Podman OCI container, DNS on port 53, web UI on port 8089, dnsmasq wildcard for `*.grab-lab.gg`, Podman base config, `systemd-resolved` disabled.

**Key files:** `modules/podman/default.nix`, `homelab/pihole/default.nix`

**Dependencies:** Stage 1 (networking), Stage 2 (Pi-hole web password in secrets). Disable `systemd-resolved` to free port 53.

**Verification steps:**
- `dig @192.168.10.X google.com` returns results (upstream DNS works)
- `dig @192.168.10.X grafana.grab-lab.gg` returns `192.168.10.X` (split DNS works)
- Pi-hole admin UI accessible at `http://192.168.10.X:8089/admin`
- Set UniFi DHCP DNS to Pi-hole IP; verify clients use Pi-hole
- `podman ps` shows pihole container running

**Estimated complexity:** Medium. Port 53 conflicts with `systemd-resolved` require explicit handling. Container volume paths must be on persistent ZFS datasets.

## Stage 4: Reverse proxy — Caddy + Cloudflare DNS-01

**What gets built:** Caddy with cloudflare DNS plugin (via `pkgs.caddy.withPlugins`), wildcard cert for `*.grab-lab.gg`, reverse proxy rules for Pi-hole admin, Cloudflare API token in sops-nix.

**Key files:** `homelab/caddy/default.nix`, secrets updated with `cloudflare_api_token`

**Dependencies:** Stage 2 (secrets), Stage 3 (Pi-hole as first backend). Cloudflare account with `grab-lab.gg` zone, API token with `Zone:Zone:Read` + `Zone:DNS:Edit`.

**Verification steps:**
- `curl -k https://pihole.grab-lab.gg/admin` loads Pi-hole UI with valid TLS
- `openssl s_client -connect 192.168.10.X:443 -servername pihole.grab-lab.gg` shows Let's Encrypt cert for `*.grab-lab.gg`
- Certificate auto-renewal: check `/var/lib/caddy` for cert files
- `journalctl -u caddy` shows successful ACME challenge

**Estimated complexity:** Medium-high. Building Caddy with plugins requires computing the `hash` value. The Cloudflare API token scoping must be precise.

## Stage 5: Monitoring — Prometheus + Grafana + Loki

**What gets built:** Prometheus with node exporter scraping, Grafana with provisioned datasources (Prometheus + Loki), Loki for log aggregation, Caddy virtual hosts for each.

**Key files:** `homelab/prometheus/default.nix`, `homelab/grafana/default.nix`, `homelab/loki/default.nix`

**Dependencies:** Stage 4 (Caddy for TLS termination). Grafana admin password in secrets.

**Verification steps:**
- `https://prometheus.grab-lab.gg` loads Prometheus UI, targets page shows node exporter UP
- `https://grafana.grab-lab.gg` loads Grafana, login works with provisioned admin credentials
- Prometheus datasource auto-provisioned in Grafana
- `https://grafana.grab-lab.gg` → Explore → Loki → shows system logs
- `promtool check config /etc/prometheus/prometheus.yml` passes

**Estimated complexity:** Medium. Multiple services to configure. Grafana provisioning requires correct datasource YAML structure.

## Stage 6: VPN — NetBird

**What gets built:** NetBird client connected to SaaS control plane (or self-hosted), routing peer advertising `192.168.10.0/24`, Pi-hole as VPN DNS server, `systemd-resolved` enabled for NetBird DNS.

**Key files:** `homelab/netbird/default.nix`, NetBird setup key in secrets

**Dependencies:** Stage 3 (Pi-hole for VPN DNS). NetBird account (app.netbird.io or self-hosted). Setup key generated in NetBird dashboard.

**Verification steps:**
- `netbird-wt0 status` shows connected
- From external device on NetBird: `ping 192.168.10.X` works
- From external device: `https://grafana.grab-lab.gg` loads (routed through VPN → Pi-hole → Caddy)
- NetBird dashboard shows server as routing peer

**Estimated complexity:** Medium. NetBird's NixOS module requires `systemd-resolved`, which may conflict with Pi-hole DNS on port 53. Careful binding configuration needed.

## Stage 7: Homepage dashboard

**What gets built:** Homepage dashboard with service widgets for all deployed services, accessible at `https://home.grab-lab.gg`.

**Key files:** `homelab/homepage/default.nix`

**Dependencies:** Stage 4 (Caddy). All services from prior stages for widget configuration.

**Verification steps:**
- `https://home.grab-lab.gg` loads dashboard
- Service widgets show status (green/red) for all configured services
- Dashboard auto-refreshes

**Estimated complexity:** Low. Well-documented NixOS module with structured config.

## Stage 8: Services — Home Assistant + Uptime Kuma

**What gets built:** Home Assistant (Podman container with `--network=host`), Uptime Kuma (native NixOS module), Caddy virtual hosts, UniFi integration in HA.

**Key files:** `homelab/home-assistant/default.nix`, `homelab/uptime-kuma/default.nix`

**Dependencies:** Stage 4 (Caddy), Stage 2 (secrets for HA). For UniFi integration: local admin user on UniFi controller.

**Verification steps:**
- `https://ha.grab-lab.gg` loads Home Assistant onboarding
- Home Assistant UniFi integration discovers devices
- `https://uptime.grab-lab.gg` loads Uptime Kuma
- Uptime Kuma monitors configured for all services
- `podman ps` shows homeassistant container running

**Estimated complexity:** Medium. Home Assistant with `--network=host` needs firewall adjustment. HA onboarding is interactive (not fully declarative).

## Stage 9: Hardening, backups, deploy-rs, and Justfile

**What gets built:** Sanoid snapshots, syncoid replication to NAS, restic backups, deploy-rs remote deployment, Justfile with all operations, firewall hardened to minimum open ports, fail2ban.

**Key files:** `homelab/backup/default.nix`, `justfile`, deploy-rs config in `flake.nix`

**Dependencies:** All prior stages. NAS accessible via SSH for syncoid or NFS/SMB mount for restic.

**Verification steps:**
- `zfs list -t snapshot` shows automatic snapshots
- `just deploy pebble` deploys successfully from dev machine
- `just build` builds without switching
- Restic backup completes: `restic -r /mnt/nas/backup/restic/homelab snapshots`
- Test restore: `restic restore latest --target /tmp/test-restore`
- `sudo nmap -sT 192.168.10.X` shows only ports 22, 53, 80, 443 open

**Estimated complexity:** Medium. NAS connectivity and ZFS send/receive setup require testing.

---
