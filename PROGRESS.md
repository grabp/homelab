# Implementation Progress

## Current Stage: 7a — VPN: VPS + NetBird Control Plane (OCI migration + embedded Dex)
## Status: IN PROGRESS

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
- **Volume directory ownership:** Pi-hole's FTL process drops from root to UID 1000 (`pihole` user) after binding port 53. SQLite WAL mode needs write access to the directory (not just the `.db` file) to create `.db-wal`/`.db-shm` lock files. `systemd.tmpfiles.rules` `d` type defaults to `root root`, causing "attempt to write a readonly database" when editing domain lists. Fixed by setting `"d /var/lib/pihole 0755 1000 1000 -"` and running `sudo chown 1000:1000 /var/lib/pihole` on the already-existing directory. See docs/NIX-PATTERNS.md Pattern 17.
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

## Stage 5: Password Management (Vaultwarden) — COMPLETE (2026-04-13)

**Files created:**
- `homelab/vaultwarden/default.nix` — Vaultwarden module: native service, SQLite backend, automatic daily backups

**Files modified:**
- `homelab/default.nix` — enabled `./vaultwarden` import
- `homelab/caddy/default.nix` — added `vault.grab-lab.gg` reverse proxy
- `machines/nixos/pebble/default.nix` — `my.services.vaultwarden.enable = true`; fixed stage number comments

**Configuration notes:**
- Native `services.vaultwarden` module (~50 MB RAM, negligible CPU)
- Port 8222/tcp (remapped from default 8000/8080 for clarity)
- SQLite database at `/var/lib/bitwarden_rs/db.sqlite3` (default)
- `backupDir = "/var/backup/vaultwarden"` creates automatic daily SQLite backups
- `SIGNUPS_ALLOWED = false` after initial account creation (still allows invitations)
- `DOMAIN = "https://vault.grab-lab.gg"` required for mobile apps and browser extensions
- Admin panel at `/admin` requires `ADMIN_TOKEN` from sops secret

**Pre-deploy action required:**
```bash
# Generate admin token
ADMIN_TOKEN=$(openssl rand -base64 48)

# Add to secrets file
just edit-secrets
# Add entry:
# vaultwarden/admin_token: |
#   ADMIN_TOKEN=<paste-generated-token-here>
```

**Post-setup actions taken:**
- `SIGNUPS_ALLOWED` flipped to `false` in `homelab/vaultwarden/default.nix` after account creation
- UniFi DHCP corrected: removed `1.1.1.1` as secondary DNS, Pi-hole only (`192.168.10.50`). iOS (and most modern OSes) query all configured DNS servers in parallel and accept the first response — a public fallback causes split-DNS domains to fail intermittently because the public server returns NXDOMAIN faster than Pi-hole returns the correct IP.

**Verification (all passed 2026-04-14):**
- [x] `curl https://vault.grab-lab.gg` returns HTTP 200
- [x] Create an account at `https://vault.grab-lab.gg`
- [x] Store a password, verify retrieval
- [x] Mobile app (Bitwarden) connects to `https://vault.grab-lab.gg` as custom server
- [x] Browser extension works with vault
- [x] `ls /var/backup/vaultwarden` shows daily SQLite backups
- [x] Admin panel accessible at `https://vault.grab-lab.gg/admin` with token

## Stage 6: Monitoring (Prometheus + Grafana + Loki) — COMPLETE (verified 2026-04-14)

**Files created:**
- `homelab/prometheus/default.nix` — Prometheus on `127.0.0.1:9090`, node exporter (`:9100`, systemd collector), 30d retention
- `homelab/grafana/default.nix` — Grafana on `127.0.0.1:3000`, declarative Prometheus + Loki datasources, admin password via `$__file{...}` from sops secret
- `homelab/loki/default.nix` — Loki on `127.0.0.1:3100` (tsdb/v13 schema, filesystem storage, 30d retention), Promtail reading journald

**Files modified:**
- `homelab/default.nix` — uncommented prometheus/grafana/loki imports
- `homelab/caddy/default.nix` — added `@grafana` and `@prometheus` virtual hosts
- `machines/nixos/pebble/default.nix` — enabled the three services

**Configuration notes:**
- All three services bind to `127.0.0.1` only; Caddy exposes Grafana and Prometheus via TLS
- Grafana admin password uses `$__file{/run/secrets/grafana/admin_password}` syntax (Grafana INI native interpolation); if this fails at runtime, fallback is `EnvironmentFile` with `GF_SECURITY_ADMIN_PASSWORD=...`
- Promtail port 3031 (internal), pushes journald to Loki at `localhost:3100`
- Loki `http_listen_address` — verify key name during first build (may surface as Nix eval error)
- No firewall changes needed: ports 80/443 already open via Caddy

**Pre-deploy action required:**
```bash
just edit-secrets
# Add (plaintext password, single line, no key=value wrapper):
# grafana/admin_password: "YourStrongPasswordHere"
```

**Bugs fixed during deployment:**
1. **Loki compactor**: `compactor.delete_request_store = "filesystem"` required when `retention_enabled = true` — Loki's config validator rejects the build without it.
2. **Promtail 226/NAMESPACE**: NixOS promtail module sets `PrivateMounts=true` + `ReadWritePaths=/var/lib/promtail` but does not declare `StateDirectory`, so the directory is never created. systemd tries to bind-mount the path into the private namespace at startup and fails with `226/NAMESPACE` if it's absent. Fixed with `systemd.tmpfiles.rules = [ "d /var/lib/promtail 0750 promtail promtail -" ]`.

**Verification (all passed 2026-04-14):**
- [x] `systemctl status prometheus grafana loki promtail` — all active
- [x] `https://prometheus.grab-lab.gg` loads; Targets page shows node exporter **UP**
- [x] `https://grafana.grab-lab.gg` loads; login with `admin` + sops password
- [x] Grafana → Connections → Prometheus datasource → Test: green
- [x] Grafana → Connections → Loki datasource → Test: green
- [x] Grafana → Explore → Loki → `{job="systemd-journal"}` returns logs
## Stage 7a: VPN — VPS Provisioning + NetBird Control Plane (OCI containers) — IN PROGRESS

**Architecture change:** Switching from Zitadel Cloud IdP + separate management/signal images to **embedded Dex IdP** (built into `netbirdio/netbird:management-latest` since v0.62.0). NetBird server uses `virtualisation.oci-containers` (NOT `services.netbird.server` — that module is not production-ready as of nixos-25.11). Native NixOS Caddy replaces nginx for TLS termination.

**Status:** Infrastructure deployed and verified; IdP migration to embedded Dex in progress. Setup wizard not yet completed. See decision log below.

**Files created:**
- `machines/nixos/vps/disko.nix` — ext4 disk layout for Hetzner CX22 (`/dev/sda`, GPT + EF02 BIOS boot partition)
- `machines/nixos/vps/default.nix` — base VPS config: GRUB boot, virtio kernel modules, sops from `vps.yaml`, ACME defaults
- `machines/nixos/vps/netbird-server.nix` — NetBird control plane: OCI containers (management + signal + dashboard) + native coturn + nginx

**Files modified:**
- `flake.nix` — added `mkNixos "vps"` call alongside pebble
- `flakeHelpers.nix` — `deployHostname` now returns `vars.vpsIP` (IP address) for VPS, not domain name (Pattern 18)
- `.sops.yaml` — added VPS age key and `vps.yaml` creation rule
- `justfile` — added `gen-vps-hostkey`, `provision-vps`, `deploy-vps`, `ssh-vps` (uses IP `204.168.181.110`)
- `homelab/pihole/default.nix` — added `address=/netbird.grab-lab.gg/${vars.vpsIP}` for split-DNS exception
- `machines/nixos/vars.nix` — added `vpsIP = "204.168.181.110"`

**Configuration:**
- OCI containers via `virtualisation.oci-containers` (Podman): `netbirdio/management`, `netbirdio/signal`, `netbirdio/dashboard`
- Native `services.coturn` — TURN relay, ACME cert, HMAC secret via `static-auth-secret-file`
- Native `services.nginx` — reverse proxy for dashboard (`:8080`), REST API (`:8011`), gRPC management + signal (`:10000`)
- IdP: Zitadel Cloud free tier (OIDC/PKCE) — issuer `grablab-zitadel-cloud-70oyna.eu1.zitadel.cloud`
- `management.json` generated at runtime by systemd oneshot (`netbird-management-config`) using `jq` to inject sops secrets
- ACME: HTTP-01 challenge via nginx (public VPS IP); `services.nginx.enable = true` required explicitly
- `users.users.turnserver.extraGroups = ["nginx"]` — coturn reads ACME certs via nginx group membership
- 2 secrets in `secrets/vps.yaml`: `netbird/turn_password`, `netbird/encryption_key`

**Bugs fixed during deployment:**
1. **Hetzner uses SeaBIOS (BIOS), not UEFI**: VPS stuck at "Booting from Hard disk..." — switched from systemd-boot to GRUB with EF02 (BIOS boot) partition in disko.nix
2. **Missing virtio kernel modules**: VPS boot failed with "Timed out waiting for device disk-main-root" — added `boot.initrd.availableKernelModules = ["virtio_pci" "virtio_blk" "virtio_scsi" "sd_mod" "sr_mod"]`
3. **Coturn permission denied on secrets**: sops secrets default to root-only — added `owner = "turnserver"`, `mode = "0440"` for `netbird/turn_password`
4. **deploy-rs used domain name, deployed to wrong machine**: SSH to `netbird.grab-lab.gg` resolved to pebble (192.168.10.50) instead of VPS (204.168.181.110), broke pebble with VPS config — added Pattern 18 (always use IPs), updated `flakeHelpers.nix` and `justfile` to use IPs
5. **Ports 80/443 not open for ACME**: nginx module doesn't auto-open firewall ports — added `networking.firewall.allowedTCPPorts = [80 443]` to VPS config
6. **Pi-hole didn't pick up DNS override**: Activation script updated config file but container wasn't restarted — must restart Pi-hole container after dnsmasq config changes (`sudo systemctl restart podman-pihole.service`)
7. **ACME assertion error**: `security.acme.certs.${domain}.group = lib.mkForce "turnserver"` triggers assertion requiring a challenge method — fixed by using `users.users.turnserver.extraGroups = ["nginx"]` instead
8. **Dashboard missing AUTH_AUDIENCE**: `netbirdio/dashboard` image requires `AUTH_AUDIENCE` env var explicitly — must be set to Zitadel project ID
9. **nginx not starting**: `services.nginx.virtualHosts` does NOT auto-enable nginx — `services.nginx.enable = true` must be set explicitly

**Pre-deploy workflow (completed):**
1. Created Hetzner CX22 VPS at IP `204.168.181.110`
2. Created Cloudflare DNS A record: `netbird.grab-lab.gg → 204.168.181.110` (DNS only, no proxy)
3. Generated SSH host key via `just gen-vps-hostkey`
4. Added VPS age key to `.sops.yaml`
5. Created `secrets/vps.yaml` with TURN password and encryption key
6. Provisioned via `just provision-vps 204.168.181.110`
7. Deployed firewall fix via `just deploy-vps`
8. Deployed pebble with Pi-hole DNS override via `just deploy pebble`
9. Restarted Pi-hole to load split-DNS config

**Verification (all passed 2026-04-14):**
- [x] All NetBird services running on VPS: nginx, netbird-management, netbird-signal, coturn
- [x] TLS certificate from Let's Encrypt (E8 CA, expires July 2026)
- [x] VPS firewall allows ports 22, 80, 443, 3478, 3479, 5349, 5350, 49152-65535
- [x] `https://netbird.grab-lab.gg` loads NetBird dashboard with valid TLS
- [x] Pi-hole split-DNS: `netbird.grab-lab.gg → 204.168.181.110` (VPS), `grafana.grab-lab.gg → 192.168.10.50` (pebble)
- [ ] Setup wizard completes: admin account created — **TODO**
- [ ] Setup key created in Dashboard → Setup Keys (reusable, "homelab-servers" group) — **TODO**
- [ ] Setup key encrypted into `secrets/secrets.yaml` (needed for Stage 7b) — **TODO**

## Stage 7b: VPN — Homelab Client + Routes + DNS + ACLs — NOT STARTED
## Stage 7c: Identity Provider — Kanidm — NOT STARTED
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
- VPS deployment: Podman OCI containers (`netbirdio/*` images) — chosen over native `services.netbird.server` (sparse docs, complex OIDC startup issues) and Docker Compose
- DNSStubListener=no is the correct Pi-hole + NetBird coexistence solution
- Route advertisement (192.168.10.0/24) configured in NetBird Dashboard, not NixOS
- Stage 6 prerequisite: VPS must be running before homelab client can connect

### IdP Strategy + NetBird OCI Migration — 2026-04-15

**Decision 1: NetBird server via OCI containers, not native NixOS module**
- `services.netbird.server` exists in nixpkgs but is not production-ready as of nixos-25.11
- Configuration failures during testing: unclear option interactions, sparse documentation, complex OIDC chicken-and-egg startup ordering
- Switched to `virtualisation.oci-containers` on NixOS VPS — same container images the official Docker Compose setup uses, but managed declaratively by NixOS
- Native NixOS Caddy replaces nginx for TLS termination (same module as pebble, consistent pattern)
- Documented in: docs/ARCHITECTURE.md (isolation table), docs/SERVICE-CONFIGS.md, docs/NIX-PATTERNS.md (Patterns 19–20), docs/STAGES.md (Stage 7a), docs/NETBIRD-SELFHOSTED.md

**Decision 2: Embedded Dex for NetBird auth + Kanidm on homelab for all service SSO**
- **Tier 1 — VPS:** NetBird's embedded Dex (built into `netbirdio/netbird:management-latest` since v0.62.0) handles VPN authentication only. Zero configuration, zero extra RAM. Eliminates Zitadel Cloud dependency.
- **Tier 2 — pebble:** Kanidm (`services.kanidm`) handles all homelab service SSO (OIDC + LDAP). ~50–80 MB RAM. Native NixOS module with declarative OAuth2 client provisioning.
- **Why two tiers:** Chicken-and-egg — need VPN to reach homelab IdP, but need IdP to authenticate VPN. Embedded Dex on VPS breaks the deadlock.
- **New Stage 7c:** Kanidm deployment added to STAGES.md (after 7b, before Stage 8; blocks Outline/Immich/etc.)
- Documented in: docs/IDP-STRATEGY.md (new), docs/ARCHITECTURE.md (Identity & Authentication section), docs/SERVICE-CONFIGS.md (Kanidm entry + auth notes per service), docs/NIX-PATTERNS.md (Patterns 21–23), docs/STAGES.md (Stage 7c), docs/STRUCTURE.md (kanidm/ module)
