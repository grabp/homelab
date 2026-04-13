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

## Stage 5: Password Management — Vaultwarden

**What gets built:** Vaultwarden (Bitwarden-compatible server) on pebble, with SQLite backend, Caddy reverse proxy, automatic daily backups via `backupDir`.

**Key files:** `homelab/vaultwarden/default.nix`

**Dependencies:** Stage 4 (Caddy for TLS termination), Stage 2 (secrets for admin token).

**Rationale:** Vaultwarden is a critical service (~50 MB RAM) that must remain accessible even when machine 2 (boulder) is down for maintenance. Unlike media services that can tolerate downtime, password access is essential for daily operations.

**Verification steps:**
- `https://vault.grab-lab.gg` loads Vaultwarden web vault with valid TLS
- Create an account, store a password, verify retrieval
- Mobile app (Bitwarden) connects to custom server URL
- Browser extension works with vault
- `ls /var/lib/vaultwarden/backups` shows daily SQLite backups
- Admin panel accessible at `/admin` with token

**Estimated complexity:** Low-medium. Native module is well-documented. Main consideration is backup strategy for this critical service.

## Stage 6: Monitoring — Prometheus + Grafana + Loki

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

## Stage 7a: VPN — VPS provisioning + NetBird control plane

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

## Stage 7b: VPN — Homelab NetBird client + routes + DNS + ACLs

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

## Stage 8: Homepage dashboard

**What gets built:** Homepage dashboard with service widgets for all deployed services, accessible at `https://home.grab-lab.gg`.

**Key files:** `homelab/homepage/default.nix`

**Dependencies:** Stage 4 (Caddy). All services from prior stages for widget configuration.

**Verification steps:**
- `https://home.grab-lab.gg` loads dashboard
- Service widgets show status (green/red) for all configured services
- Dashboard auto-refreshes

**Estimated complexity:** Low. Well-documented NixOS module with structured config.

## Stage 9a: Services — Mosquitto + HACS + Home Assistant + Uptime Kuma

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

## Stage 9b: Services — Voice Pipeline + ESPHome + Matter Server

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

## Stage 10: Hardening, backups, deploy-rs, and Justfile

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

# Phase 2: Machine 2 (boulder) — HP EliteDesk 705 G4

**Prerequisite:** Complete all Phase 1 stages (1–10) on pebble before starting Phase 2. Machine 1 should be stable, monitored, and backed up.

See `docs/SECOND-MACHINE.md` for detailed hardware specs and service configurations.

## Stage 11: Base system — boulder hardware provisioning

**What gets built:** NixOS on boulder via disko (ZFS), SSH access, add to flake as second machine, node_exporter + promtail for monitoring, NetBird client for VPN access.

**Key files:** `machines/nixos/boulder/{default,disko,hardware}.nix`, update `flake.nix` with `mkNixos "boulder"`

**Dependencies:** Physical hardware ready, static IP assigned (192.168.10.51), SSH key in place.

**Verification steps:**
- `ssh admin@192.168.10.51` works
- `zpool status` shows healthy pool
- `just deploy boulder` deploys successfully
- Prometheus targets show boulder's node_exporter as UP
- Loki receives logs from boulder's promtail
- `netbird-wt0 status` shows connected to control plane

**Estimated complexity:** Low-medium. Same process as pebble Stage 1, but second time is faster.

## Stage 12: PostgreSQL shared instance

**What gets built:** Single PostgreSQL server for Outline, Vikunja, and Paperless-ngx. Each service gets its own database with separate credentials stored in sops.

**Key files:** `homelab/postgresql/default.nix` or configure in boulder's `default.nix`

**Dependencies:** Stage 11 (base system).

**Verification steps:**
- `systemctl status postgresql` shows active
- `psql -U postgres -l` lists databases
- Databases created: `outline`, `vikunja`, `paperless`
- Each database user has appropriate permissions

**Estimated complexity:** Low. Native module is straightforward.

## Stage 13: Paperless-ngx + Stirling-PDF

**What gets built:** Paperless-ngx document management (native module) with NAS storage for documents, Stirling-PDF toolkit (container) for PDF operations.

**Key files:** `homelab/paperless/default.nix`

**Dependencies:** Stage 12 (PostgreSQL), NAS mount for `/mnt/nas/documents`.

**Verification steps:**
- `https://paperless.grab-lab.gg` loads Paperless web UI
- Document upload → OCR processing → searchable
- `https://pdf.grab-lab.gg` loads Stirling-PDF
- PDF operations (merge, split, convert) work

**Estimated complexity:** Medium. NFS mount dependencies require careful systemd ordering.

## Stage 14: Immich photo management

**What gets built:** Immich server (Podman containers: server, machine-learning, Redis) with PostgreSQL backend, NAS storage for photos, ML-based face/object recognition.

**Key files:** Container configs in boulder's default.nix or dedicated `homelab/immich/default.nix`

**Dependencies:** Stage 12 (PostgreSQL), NAS mount for `/mnt/nas/photos`.

**Verification steps:**
- `https://immich.grab-lab.gg` loads Immich web UI
- Photo upload works
- Face recognition processes photos
- Mobile app connects and syncs

**Estimated complexity:** Medium-high. Multi-container orchestration, ML inference can be resource-intensive.

## Stage 15: Jellyfin media server

**What gets built:** Jellyfin media server (native module preferred, container as fallback) with VAAPI hardware transcoding, NAS storage for media library.

**Key files:** `homelab/jellyfin/default.nix`

**Dependencies:** Stage 11 (GPU access configured), NAS mount for `/mnt/nas/media`.

**Verification steps:**
- `https://jellyfin.grab-lab.gg` loads Jellyfin web UI
- Media library scanned from NAS
- Playback works (direct play and transcoding)
- VAAPI transcoding active (check Jellyfin dashboard)
- DLNA discovery works on LAN

**Estimated complexity:** Medium. VAAPI configuration requires GPU permissions.

## Stage 16: Productivity apps — Outline, Vikunja, Karakeep, Actual Budget

**What gets built:** Outline wiki (container), Vikunja tasks (container), Karakeep bookmarks (container), Actual Budget (container). All on port-remapped configs to avoid conflicts.

**Key files:** Container configs in boulder's default.nix or individual modules

**Dependencies:** Stage 12 (PostgreSQL for Outline, Vikunja).

**Verification steps:**
- `https://wiki.grab-lab.gg` — Outline loads
- `https://tasks.grab-lab.gg` — Vikunja loads
- `https://bookmarks.grab-lab.gg` — Karakeep loads
- `https://budget.grab-lab.gg` — Actual Budget loads
- Data persists across container restarts

**Estimated complexity:** Low-medium. Multiple containers but each is straightforward.

## Stage 17: Windows VM — libvirt/QEMU

**What gets built:** libvirt/QEMU virtualization enabled, Windows 10/11 VM for occasional use cases (specific software, testing).

**Key files:** VM config stored in `/var/lib/libvirt/`, virt-manager for GUI management

**Dependencies:** Stage 11 (base system).

**Verification steps:**
- `virt-manager` launches on admin workstation
- Windows VM boots and is usable
- RDP access works over LAN/VPN
- VM does not consume resources when stopped

**Estimated complexity:** Low. libvirt module is well-documented.

## Stage 18: Whisper migration — move STT from pebble to boulder

**What gets built:** Wyoming Faster-Whisper service on boulder (same config as pebble), Home Assistant on pebble reconfigured to use boulder's Whisper endpoint.

**Key files:** Add Wyoming config to boulder, update HA configuration on pebble

**Dependencies:** Stage 11 (boulder running), Stage 9b complete on pebble (voice pipeline tested).

**Verification steps:**
- Wyoming Whisper running on boulder:10300
- Home Assistant voice assistant uses `boulder.lan:10300` for STT
- Voice commands work with new endpoint
- Pebble's Whisper service disabled
- pebble RAM usage reduced by ~500–800 MB

**Estimated complexity:** Low. Config migration only.

---

# Stage summary

| Phase | Stage | Name | Machine |
|-------|-------|------|---------|
| 1 | 1 | Base system | pebble |
| 1 | 2 | Secrets management | pebble |
| 1 | 3 | DNS (Pi-hole) | pebble |
| 1 | 4 | Reverse proxy (Caddy) | pebble |
| 1 | 5 | Password management (Vaultwarden) | pebble |
| 1 | 6 | Monitoring | pebble |
| 1 | 7a | VPN — VPS provisioning | vps |
| 1 | 7b | VPN — Homelab client | pebble |
| 1 | 8 | Homepage dashboard | pebble |
| 1 | 9a | HA + MQTT + HACS | pebble |
| 1 | 9b | Voice + ESPHome + Matter | pebble |
| 1 | 10 | Hardening + backups | pebble + vps |
| 2 | 11 | Base system | boulder |
| 2 | 12 | PostgreSQL | boulder |
| 2 | 13 | Paperless + Stirling-PDF | boulder |
| 2 | 14 | Immich | boulder |
| 2 | 15 | Jellyfin | boulder |
| 2 | 16 | Productivity apps | boulder |
| 2 | 17 | Windows VM | boulder |
| 2 | 18 | Whisper migration | boulder + pebble |

---
