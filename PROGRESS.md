# Implementation Progress

## Current Stage: 5 — Password Management (Vaultwarden)
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

## Stage 3: DNS (Pi-hole) — COMPLETE (implemented 2026-04-12)

**Files created:**
- `modules/podman/default.nix` — Podman base config, OCI backend
- `homelab/pihole/default.nix` — Pi-hole module: OCI container, port 53 + 8089, wildcard split DNS

**Files modified:**
- `flake.nix` — added `./modules/podman` to pebble modules
- `homelab/default.nix` — enabled `./pihole` import
- `machines/nixos/pebble/default.nix` — `my.services.pihole.enable = true`

**Configuration notes:**
- Image: `pihole/pihole:2025.02.1` (Pi-hole v6)
- Web UI: port 8089 (mapped from container port 80)
- Split DNS: `address=/grab-lab.gg/192.168.10.50` written to `/var/lib/pihole-dnsmasq/04-grab-lab.conf` via `system.activationScripts`; `FTLCONF_misc_etc_dnsmasq_d=true` enables reading `/etc/dnsmasq.d/` (off by default in v6)
- `FTLCONF_misc_dnsmasq_lines` is unusable for `address=` directives — Pi-hole v6 splits array items on `=`, discarding everything after the first `=`
- Conditional forwarding (.lan/.local → router): `server=/domain/ip` in dnsmasq conf-dir files is a known Pi-hole v6 bug (#6279, returns 0ms NXDOMAIN without forwarding); use `FTLCONF_dns_revServers` instead — format: `"true,CIDR,server#port,domain"`, semicolon-separated for multiple domains
- Secret: `pihole/env` in `secrets/secrets.yaml` must contain `FTLCONF_webserver_api_password=<password>`
- `services.resolved.enable = false` — Stage 6b (NetBird) re-enables it with `DNSStubListener=no`
- **Netavark/firewall ordering bug:** when `nixos-rebuild switch` reloads `firewall.service` (any change to `networking.firewall.*`), NixOS flushes all iptables chains including `NETAVARK_*`. If the Pi-hole container isn't restarted, its DNAT rules for port 53 are gone and external DNS queries time out. Fixed via `systemd.services.podman-pihole = { after = ["firewall.service"]; partOf = ["firewall.service"]; }` — applies to ALL future OCI containers that publish ports.
- `deploy.nodes.*.hostname` must be the actual IP/FQDN — fixed via `deployHostname` in `flakeHelpers.nix`
- `nix.settings.trusted-users = ["root" "admin"]` required for deploy-rs to push store paths

**Pre-deploy action required:**
```bash
just edit-secrets  # add: pihole/env: "FTLCONF_webserver_api_password=<your-password>"
```

**Verification:**
- [x] `podman ps` shows pihole container running
- [x] `dig @192.168.10.50 google.com` returns results (upstream DNS works)
- [x] `dig @192.168.10.50 grafana.grab-lab.gg` returns `192.168.10.50` (split DNS works)
- [x] Pi-hole admin UI at `http://192.168.10.50:8089/admin` loads
- [x] Set UniFi DHCP DNS to `192.168.10.50`; verify clients resolve via Pi-hole
- [x] `dig @192.168.10.50 unifi.lan` returns router answer (conditional forwarding works)
## Stage 4: Reverse Proxy (Caddy) — COMPLETE (2026-04-13)

**Files created:**
- `homelab/caddy/default.nix` — Caddy module: `withPlugins` Cloudflare DNS build, wildcard cert, Pi-hole reverse proxy

**Files modified:**
- `homelab/default.nix` — enabled `./caddy` import
- `machines/nixos/pebble/default.nix` — `my.services.caddy.enable = true`; added `1.1.1.1` fallback nameserver
- `homelab/pihole/default.nix` — added `partOf`/`after firewall.service` to `podman-pihole` (Netavark fix)

**Configuration notes:**
- `pkgs.caddy.withPlugins` compiles in `caddy-dns/cloudflare` for DNS-01 ACME — standard `pkgs.caddy` has no DNS plugins
- Plugin pinned to `a8737d095ad5` (2026-03-23) — compatible with libdns v1.1.0 / Caddy 2.11.x; old July 2024 commit broke on `libdns.Record` field renames
- Wildcard cert `*.grab-lab.gg` via Cloudflare DNS-01; `resolvers 1.1.1.1` in TLS block bypasses Pi-hole so ACME lookups don't loop
- `CLOUDFLARE_API_TOKEN` injected from sops secret `caddy/env` via `EnvironmentFile` on the caddy systemd service
- Token scopes required: Zone:Zone:Read + Zone:DNS:Edit (scoped to grab-lab.gg zone only)
- **Netavark fix** (see Stage 3 notes): `podman-pihole` now restarts with `firewall.service`; apply the same `partOf`/`after` pattern to every future OCI container that publishes ports (ESPHome, Matter Server, Home Assistant)

**Verification:**
- [x] `curl https://pihole.grab-lab.gg/admin` loads Pi-hole UI with valid TLS
- [x] Let's Encrypt wildcard cert `*.grab-lab.gg`, issuer E8 CA, valid 2026-04-12 → 2026-07-11
- [x] Certificate files present in `/var/lib/caddy/.local/share/caddy/certificates/`
- [x] ACME account registration retry loop — resolved by deploying `1.1.1.1` DNS fallback

## Stage 5: Password Management (Vaultwarden) — NOT STARTED
## Stage 6: Monitoring (Prometheus + Grafana + Loki) — NOT STARTED
## Stage 7a: VPN — VPS Provisioning + NetBird Control Plane — NOT STARTED
## Stage 7b: VPN — Homelab Client + Routes + DNS + ACLs — NOT STARTED
## Stage 8: Homepage Dashboard — NOT STARTED
## Stage 9a: Services (Mosquitto + HACS + Home Assistant + Uptime Kuma) — NOT STARTED
## Stage 9b: Services (Voice Pipeline + ESPHome + Matter Server) — NOT STARTED
## Stage 10: Hardening, Backups, deploy-rs — NOT STARTED

## Phase 2: Machine 2 (boulder) — NOT STARTED
See docs/STAGES.md for Stages 11-18

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

---

### NetBird Self-Hosted VPN Research — incorporated 2026-04-12

Researched self-hosting NetBird behind CGNAT. Findings incorporated into all architecture docs. **Scope change: flake now manages two machines** (pebble homelab + Hetzner VPS).

**docs/NETBIRD-SELFHOSTED.md** — primary research document (new)

**docs/ARCHITECTURE.md** additions:
- Split NetBird row in isolation table: client (native, pebble) vs server (Docker Compose, VPS)
- Updated network topology diagram to show VPS, CGNAT boundary, relay/P2P paths
- New section: "VPS control plane" — CGNAT implications, Hetzner CX22 recommendation, VPS ports, DNS records, split DNS via match-domain, `DNSStubListener=no` coexistence solution, security model

**docs/STRUCTURE.md** changes:
- `machines/nixos/vps/` added alongside `pebble/` (default.nix, disko.nix, netbird-server.nix)
- `secrets/vps.yaml` added for VPS secrets
- `.sops.yaml` note: must contain age keys for all three identities (admin, pebble, VPS)
- flake.nix and flakeHelpers.nix descriptions updated for two-machine setup

**docs/STAGES.md** changes:
- Stage 6 split into Stage 6a (VPS provisioning + NetBird server) and Stage 6b (homelab client + routes + DNS + ACLs)
- Stage 9 updated with VPS hardening and NetBird ACL policy requirements

**docs/NIX-PATTERNS.md** additions:
- Pattern 12: Multi-machine flake with deploy-rs (pebble + VPS)
- Pattern 13: nixos-anywhere VPS provisioning + minimal ext4 disko
- Pattern 14: NetBird client with sops-nix setup key + self-hosted management URL
- Pattern 15: systemd-resolved with DNSStubListener=no (NetBird + Pi-hole coexistence)

**docs/SERVICE-CONFIGS.md** changes:
- NetBird entry completely rewritten: server (VPS, Docker Compose primary / NixOS module experimental) + client (homelab, native)
- All VPS ports, DNS records, management URL requirement, embedded Dex IdP documented

**justfile** additions:
- `provision-vps IP` — nixos-anywhere initial provisioning
- `deploy-vps` — deploy-rs to VPS
- `ssh-vps` — SSH to VPS
- `netbird-status` — run `netbird-wt0 status -d` on homelab

**Key decisions recorded:**
- VPS: Hetzner CX22 at €3.79/month
- VPS deployment: Docker Compose initially (lower risk), migrate to NixOS in Stage 9
- DNSStubListener=no is the correct Pi-hole + NetBird coexistence solution
- Route advertisement (192.168.10.0/24) configured in NetBird Dashboard, not NixOS
- Stage 6 prerequisite: VPS must be running before homelab client can connect
