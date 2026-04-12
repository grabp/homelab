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

## Stage 6a: VPN — VPS provisioning + NetBird control plane

**What gets built:** Hetzner CX22 VPS provisioned via `nixos-anywhere`, NixOS deployed with `machines/nixos/vps/`, NetBird control plane running (either `services.netbird.server` NixOS module or Docker Compose via the official quickstart script), TLS via ACME/Let's Encrypt, NetBird dashboard accessible at `https://netbird.grab-lab.gg`. Setup keys and VPS secrets stored in `secrets/vps.yaml`.

**Key files:** `machines/nixos/vps/{default,disko,netbird-server}.nix`, `secrets/vps.yaml`, `.sops.yaml` updated with VPS age key

**Dependencies:** Stage 2 (sops-nix for secrets). Hetzner account. DNS A record `netbird.grab-lab.gg → <VPS_IP>` created (DNS only in Cloudflare — **not** proxied, gRPC requires direct TCP). VPS SSH host key extracted via `ssh-keyscan | ssh-to-age` to get the VPS age key.

**Deployment options (choose one):**
- **NixOS path (preferred):** `just provision-vps <VPS_IP>` — runs `nixos-anywhere --flake .#vps root@<VPS_IP>`
- **Docker path (lower risk initially):** SSH into a plain Ubuntu VPS, run `curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh | bash` with `NETBIRD_DOMAIN=netbird.grab-lab.gg`

**Verification steps:**
- `https://netbird.grab-lab.gg` loads the NetBird dashboard; TLS certificate valid
- Setup wizard completes: admin account created
- Setup key created in Dashboard → Setup Keys (reusable key, "homelab-servers" group)
- Key encrypted into `secrets/vps.yaml` with `just edit-secrets` (or `sops secrets/vps.yaml`)

**Estimated complexity:** Medium. NixOS path requires `nixos-anywhere` and computing the VPS age key. Docker path is faster but leaves the VPS unmanaged by Nix. The `services.netbird.server` NixOS module has sparse documentation — treat all options as ⚠️ VERIFY.

## Stage 6b: VPN — Homelab NetBird client + routes + DNS + ACLs

**What gets built:** NetBird client on pebble (`services.netbird.clients.wt0`), `systemd-resolved` with `DNSStubListener=no` for Pi-hole coexistence, route advertisement for `192.168.10.0/24` configured in the NetBird dashboard, match-domain nameserver pointing VPN clients to Pi-hole for `grab-lab.gg`, ACL policies hardened.

**Key files:** `homelab/netbird/default.nix`, `secrets/secrets.yaml` updated with NetBird setup key

**Dependencies:** Stage 6a (control plane running, setup key exists). Stage 3 (Pi-hole for VPN DNS). Route advertisement requires IP forwarding (`services.netbird.useRoutingFeatures = "both"`).

**⚠️ Management URL:** The NixOS module may not support setting the management URL declaratively. After first deploy, run once:
```
netbird-wt0 up --management-url https://netbird.grab-lab.gg --setup-key $(cat /run/secrets/netbird-setup-key)
```

**Verification steps (CGNAT-aware):**
- `netbird-wt0 status -d` shows connected; check `ICE candidate` field — expect `relay` behind CGNAT
- `systemctl status systemd-resolved` shows running; `port 53` is held by Pi-hole, not resolved stub
- Dashboard → Network Routes shows `192.168.10.0/24` active with pebble as routing peer
- Dashboard → DNS shows `grab-lab.gg` match-domain pointing to Pi-hole overlay IP
- From phone on mobile data (not LAN): install NetBird app, authenticate, reach `https://grafana.grab-lab.gg`
- `dig @<pihole-overlay-ip> grafana.grab-lab.gg` returns `192.168.10.X`
- If connection appears "Connected" but traffic stops: `netbird-wt0 down && netbird-wt0 up` (stale relay workaround)

**Estimated complexity:** Medium-high. The `DNSStubListener=no` coexistence requires care. Management URL may need a one-time manual step. CGNAT means relay is expected — don't troubleshoot P2P as a failure.

## Stage 7: Homepage dashboard

**What gets built:** Homepage dashboard with service widgets for all deployed services, accessible at `https://home.grab-lab.gg`.

**Key files:** `homelab/homepage/default.nix`

**Dependencies:** Stage 4 (Caddy). All services from prior stages for widget configuration.

**Verification steps:**
- `https://home.grab-lab.gg` loads dashboard
- Service widgets show status (green/red) for all configured services
- Dashboard auto-refreshes

**Estimated complexity:** Low. Well-documented NixOS module with structured config.

## Stage 8a: Services — Mosquitto + HACS + Home Assistant + Uptime Kuma

**What gets built:** Mosquitto MQTT broker (native), Home Assistant (Podman container with `--network=host`), HACS auto-installed via systemd oneshot, Uptime Kuma (native NixOS module), Caddy virtual hosts for HA and Uptime Kuma, UniFi integration in HA.

**Key files:** `homelab/mosquitto/default.nix`, `homelab/home-assistant/default.nix`, `homelab/uptime-kuma/default.nix`

**Dependencies:** Stage 4 (Caddy), Stage 2 (secrets for HA). For UniFi integration: local admin user on UniFi controller. Mosquitto password hashes generated locally with `mosquitto_passwd`.

**Verification steps:**
- `https://ha.grab-lab.gg` loads Home Assistant onboarding
- Home Assistant UniFi integration discovers devices
- `systemctl status mosquitto` shows active; HA MQTT integration connects to `127.0.0.1:1883`
- `cat /var/lib/homeassistant/custom_components/hacs/__init__.py` confirms HACS installed
- `https://uptime.grab-lab.gg` loads Uptime Kuma
- `podman ps` shows homeassistant container running

**Estimated complexity:** Medium. Home Assistant `--network=host` needs firewall adjustment. HA onboarding is interactive (not fully declarative). HACS requires completing GitHub OAuth device flow in HA UI after first boot.

## Stage 8b: Services — Voice Pipeline + ESPHome + Matter Server

**What gets built:** Wyoming voice pipeline (Faster-Whisper STT, Piper TTS, OpenWakeWord — all native NixOS modules), ESPHome dashboard (Podman container with `--network=host`), Matter Server (Podman container with `--network=host`), Avahi mDNS, Wyoming integrations configured in HA UI.

**Key files:** `homelab/wyoming/default.nix`, `homelab/matter-server/default.nix`; ESPHome added to `homelab/home-assistant/default.nix` or its own module.

**Dependencies:** Stage 8a (Home Assistant running). Avahi required for ESPHome mDNS device discovery. IPv6 enabled on host for Matter.

**Verification steps:**
- `systemctl status wyoming-faster-whisper-main wyoming-piper-main wyoming-openwakeword` — all active
- In HA UI: Settings → Voice assistants → create pipeline using Whisper + Piper + OpenWakeWord
- Hold the microphone button in the HA mobile app and speak a command — HA responds with TTS
- `https://esphome.grab-lab.gg` (or direct port 6052) loads ESPHome dashboard; existing ESP devices discovered
- Matter integration configured at `ws://127.0.0.1:5580/ws`; commissioning a Matter device succeeds
- `podman ps` shows esphome and matter-server containers running

**Estimated complexity:** Medium. The ProcSubset fix for faster-whisper is critical (see docs/NIX-PATTERNS.md Pattern 10 and docs/ARCHITECTURE.md). ESPHome's `--network=host` avoids mDNS issues. Matter requires IPv6 enabled and IPv6 forwarding disabled.

## Stage 9: Hardening, backups, deploy-rs, and Justfile

**What gets built:** Sanoid snapshots, syncoid replication to NAS, restic backups, deploy-rs remote deployment for both pebble and vps, Justfile with all operations, firewall hardened to minimum open ports on both machines, fail2ban, NetBird ACL policies hardened, VPS SSH restricted to admin IP.

**Key files:** `homelab/backup/default.nix`, `justfile`, deploy-rs config in `flake.nix`

**Dependencies:** All prior stages. NAS accessible via SSH for syncoid or NFS/SMB mount for restic.

**Verification steps:**
- `zfs list -t snapshot` shows automatic snapshots
- `just deploy pebble` deploys successfully from dev machine
- `just deploy-vps` deploys to VPS successfully
- `just build` builds without switching
- Restic backup completes: `restic -r /mnt/nas/backup/restic/homelab snapshots`
- Test restore: `restic restore latest --target /tmp/test-restore`
- `sudo nmap -sT 192.168.10.X` shows only ports 22, 53, 80, 443 open on pebble
- NetBird Dashboard: default "All → All" ACL policy deleted; group-scoped policies in place
- VPS: SSH access restricted to admin IP in `networking.firewall`; fail2ban active
- NetBird setup keys: reusable server key in use; personal device keys are one-off with expiration

**Estimated complexity:** Medium. NAS connectivity and ZFS send/receive setup require testing. VPS hardening is mostly firewall rules and ACL configuration.

---
