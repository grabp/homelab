# Implementation Progress

## Current Stage: 3 — DNS (Pi-hole)
## Status: NOT STARTED

---

## Stage 1: Base System — COMPLETE (verified 2026-04-11)

**Files created:**
- `flake.nix` — inputs: nixpkgs 25.11, deploy-rs, disko, sops-nix
- `flakeHelpers.nix` — `mkNixos` + `mkMerge` helpers
- `machines/nixos/vars.nix` — domain, serverIP, timezone, etc.
- `machines/nixos/_common/` — nix-settings, ssh, users, locale
- `machines/nixos/pebble/default.nix` — ZFS boot, static IP, firewall
- `machines/nixos/pebble/disko.nix` — ZFS pool (zroot) on `/dev/nvme0n1`
- `machines/nixos/pebble/hardware.nix` — generated for HP ProDesk
- `homelab/default.nix` — stub for future service modules
- `modules/networking/default.nix` — `my.networking.staticIPv4` custom module
- `users/admin/default.nix` — admin user with SSH key, passwordless sudo
- `justfile` — build, switch, deploy, secrets, gen-hostid

**Configuration notes:**
- `networking.hostId = "8423e349"` — generated during disko partitioning
- `boot.zfs.forceImportRoot = true` — required for ZFS import during boot
- Network interface: `eth0` (matches module default)

**Verification (all passed):**
- [x] Boot into NixOS from SSD
- [x] `zpool status` shows healthy pool with compression enabled
- [x] SSH login works with key-based auth
- [x] `ip addr` shows static IP `192.168.10.50/24`
- [x] `curl https://nixos.org` works (internet connectivity)
- [x] `nixos-rebuild switch --flake .` succeeds locally

---

## Stage 2: Secrets Management — COMPLETE (verified 2026-04-11)

**Files created:**
- `.sops.yaml` — age keys for admin (koksownik) and pebble
- `secrets/secrets.yaml` — encrypted secrets file

**Configuration:**
- sops-nix configured in `machines/nixos/pebble/default.nix`
- Age key derived from SSH host key (`/etc/ssh/ssh_host_ed25519_key`)
- Admin key stored at `~/.config/sops/age/keys.txt` on koksownik

**Verification (all passed):**
- [x] `sops secrets/secrets.yaml` opens editor and encrypts on save
- [x] `nixos-rebuild switch` decrypts secrets successfully
- [x] `cat /run/secrets/test_secret` shows decrypted value
- [x] Secret file permissions correct (readable by root)

---

## Stage 3: DNS (Pi-hole) — NOT STARTED
## Stage 4: Reverse Proxy (Caddy) — NOT STARTED
## Stage 5: Monitoring (Prometheus + Grafana + Loki) — NOT STARTED
## Stage 6: VPN (NetBird) — NOT STARTED
## Stage 7: Homepage Dashboard — NOT STARTED
## Stage 8a: Services (Mosquitto + HACS + Home Assistant + Uptime Kuma) — NOT STARTED
## Stage 8b: Services (Voice Pipeline + ESPHome + Matter Server) — NOT STARTED
## Stage 9: Hardening, Backups, deploy-rs — NOT STARTED

---

## Documentation Updates

### HA Companion Services Research — incorporated 2026-04-12

Researched all six HA companion services. Findings incorporated into all architecture docs:

**docs/HA-COMPANION-SERVICES.md** — primary research document (new)

**docs/SERVICE-CONFIGS.md** additions:
- Updated Home Assistant entry with companion services reference
- New sections: Mosquitto, Wyoming Whisper, Wyoming Piper, Wyoming OpenWakeWord, ESPHome, Matter Server
- Updated service module verification summary table

**docs/ARCHITECTURE.md** additions:
- Service isolation table extended with 6 new services (Mosquitto + 3 Wyoming + ESPHome + Matter Server)
- Port assignments table extended (ports 1883, 10200, 10300, 10400, 6052, 5580)
- Added `mDNS and host networking` section with Avahi config
- Added faster-whisper ProcSubset bug warning and fix

**docs/STAGES.md** changes:
- Stage 8 split into Stage 8a (Mosquitto + HACS + HA + Uptime Kuma) and Stage 8b (voice pipeline + ESPHome + Matter Server) for safer incremental deployment

**docs/NIX-PATTERNS.md** additions:
- Pattern 10: Native Wyoming service with systemd ProcSubset override
- Pattern 11: HACS auto-installation via systemd oneshot (two approaches: download-on-boot and pinned/Nix-pure)

**docs/STRUCTURE.md** additions:
- `homelab/mosquitto/`, `homelab/wyoming/`, `homelab/matter-server/` added to directory tree
- Rationale for single `wyoming/` module documented
- homelab/default.nix imports example updated

**Key decisions recorded:**
- ESPHome and Matter Server → Podman containers (native has bugs/broken deps)
- Wyoming Whisper, Piper, OpenWakeWord, Mosquitto → Native NixOS modules
- HACS → systemd oneshot (Approach A for simplicity)
- Voice services grouped in single `homelab/wyoming/` module
- ProcSubset fix is mandatory for faster-whisper
