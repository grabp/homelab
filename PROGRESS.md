# Implementation Progress

## Current Stage: Phase 2 — Stage 11 (boulder base system)
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
## Stage 7a: VPN — VPS Provisioning + NetBird Control Plane (OCI containers) — COMPLETE (2026-04-15)

**Architecture:** Embedded Dex IdP (built into `netbirdio/management:latest` since v0.62.0). NetBird server via `virtualisation.oci-containers`. Native NixOS Caddy for TLS termination. `services.netbird.server` NixOS module NOT used (not production-ready as of nixos-25.11).

**Status:** Deployed, setup wizard completed, setup key encrypted into secrets.

**Files created:**
- `machines/nixos/vps/disko.nix` — ext4 disk layout for Hetzner CX22 (`/dev/sda`, GPT + EF02 BIOS boot partition)
- `machines/nixos/vps/default.nix` — base VPS config: GRUB boot, virtio kernel modules, sops from `vps.yaml`, ACME defaults
- `machines/nixos/vps/netbird-server.nix` — NetBird control plane: OCI containers (management + signal + dashboard) + native coturn; embedded Dex via `EmbeddedIdP.Enabled = true` in management.json
- `machines/nixos/vps/caddy.nix` — native Caddy reverse proxy: HTTP-01 ACME, gRPC h2c proxy for management/signal, `/oauth2/*` proxy for embedded Dex, dashboard SPA

**Files modified:**
- `flake.nix` — added `mkNixos "vps"` call alongside pebble
- `flakeHelpers.nix` — `deployHostname` returns `vars.vpsIP` for VPS (Pattern 18)
- `.sops.yaml` — added VPS age key and `vps.yaml` creation rule
- `justfile` — added `gen-vps-hostkey`, `provision-vps`, `deploy-vps`, `ssh-vps`
- `homelab/pihole/default.nix` — added `address=/netbird.grab-lab.gg/${vars.vpsIP}` for split-DNS exception
- `machines/nixos/vars.nix` — added `vpsIP = "204.168.181.110"`

**Configuration (current — embedded Dex + Caddy):**
- OCI containers via `virtualisation.oci-containers` (Podman):
  - `netbirdio/management:latest` (`:8080`) — management REST API + gRPC + embedded Dex IdP
  - `netbirdio/signal:latest` (`:10000`) — peer coordination (still separate image in v0.68.x)
  - `netbirdio/dashboard:latest` (`:3000`) — React web UI
- `management.json`: `EmbeddedIdP.Enabled = true`, `EmbeddedIdP.Issuer = "https://netbird.grab-lab.gg/oauth2"`. `IdpManagerConfig` omitted (only for external IdPs). OIDC endpoint auto-configured by binary.
- Dashboard env: `AUTH_AUTHORITY=/oauth2`, `AUTH_CLIENT_ID=netbird-dashboard`, redirect URIs `/nb-auth` and `/nb-silent-auth`
- Native `services.coturn` — STUN/TURN relay, TLS cert from Caddy's data dir, HMAC secret via sops
- Native `services.caddy` — TLS termination via HTTP-01 ACME; gRPC h2c proxying; `/oauth2/*` → management
- `users.users.turnserver.extraGroups = ["caddy"]` — coturn reads Caddy-managed ACME certs
- `management.json` generated at runtime by systemd oneshot using `jq` to inject TURN password + encryption key
- 2 secrets in `secrets/vps.yaml`: `netbird/turn_password`, `netbird/encryption_key`

**Bugs fixed during deployment:**
1. **Hetzner uses SeaBIOS (BIOS), not UEFI**: switched from systemd-boot to GRUB with EF02 partition in disko.nix
2. **Missing virtio kernel modules**: added `boot.initrd.availableKernelModules = ["virtio_pci" "virtio_blk" "virtio_scsi" "sd_mod" "sr_mod"]`
3. **Coturn permission denied on secrets**: sops secrets default to root-only — added `owner = "turnserver"`, `mode = "0440"`
4. **deploy-rs used domain name, deployed to wrong machine**: fixed via Pattern 18 (IPs only) in `flakeHelpers.nix` and `justfile`
5. **Ports 80/443 not open for ACME**: added `networking.firewall.allowedTCPPorts = [80 443]` to VPS config
6. **Pi-hole didn't pick up DNS override**: must restart Pi-hole container after dnsmasq config changes
7. **ACME assertion error**: use `users.users.turnserver.extraGroups = ["caddy"]` instead of changing cert group
8. **nginx not starting**: `services.nginx.virtualHosts` does NOT auto-enable nginx — `services.nginx.enable = true` must be set explicitly (no longer relevant; nginx removed in favour of Caddy)
9. **Wrong image name in first migration attempt**: `netbirdio/netbird:management-latest` does NOT exist on Docker Hub. Correct image is `netbirdio/management:latest`. Signal is still a separate `netbirdio/signal:latest` image (not merged). deploy-rs rolled back automatically.
10. **Wrong embedded Dex path**: initial attempt used `/idp/` path; correct path is `/oauth2/` (the binary registers Dex routes at `/oauth2`). Dashboard redirect URIs are `/nb-auth` and `/nb-silent-auth` (not `/auth` and `/silent-auth`).
11. **Unregistered redirect_uri BAD_REQUEST**: Dex auto-registers only `/api/reverse-proxy/callback` for the dashboard client. The dashboard PKCE flow sends `/nb-auth`; Dex rejected it. Fix: add `EmbeddedIdP.DashboardRedirectURIs = ["https://${domain}/nb-auth", "https://${domain}/nb-silent-auth"]` to management.json.
12. **AUTH_REDIRECT_URI must be a relative path**: the dashboard JavaScript prepends `window.location.origin` to the value. Full URL `"https://domain/nb-auth"` produces doubled `"https://domainhttps://domain/nb-auth"`. Use `"/nb-auth"` and `"/nb-silent-auth"` (relative paths).
13. **setup_required: false blocked the setup wizard**: old `store.db` from Zitadel-era deployment caused the management server to report setup as already complete. The `/setup` page redirected straight to Dex login, but `idp.db` had no users. Fix: stop management container, delete `store.db` and `idp.db`, restart — instance reverts to `setup_required: true`.

**Pre-deploy workflow (completed):**
1. Created Hetzner CX22 VPS at IP `204.168.181.110`
2. Created Cloudflare DNS A record: `netbird.grab-lab.gg → 204.168.181.110` (DNS only, no proxy)
3. Generated SSH host key via `just gen-vps-hostkey`
4. Added VPS age key to `.sops.yaml`
5. Created `secrets/vps.yaml` with TURN password and encryption key
6. Provisioned via `just provision-vps 204.168.181.110`
7. Deployed pebble with Pi-hole DNS override via `just deploy pebble`
8. Restarted Pi-hole to load split-DNS config

**Verification (passed 2026-04-15):**
- [x] `podman ps` on VPS shows 3 containers: `netbird-management` (:8080), `netbird-signal` (:10000), `netbird-dashboard` (:3000)
- [x] `systemctl is-active caddy coturn` — both active
- [x] `curl https://netbird.grab-lab.gg/oauth2/.well-known/openid-configuration` returns Dex discovery JSON with `"issuer": "https://netbird.grab-lab.gg/oauth2"`
- [x] `https://netbird.grab-lab.gg` loads NetBird dashboard (HTTP 200)
- [x] TLS certificate from Let's Encrypt (E8 CA), served by Caddy via HTTP-01 ACME
- [x] Pi-hole split-DNS: `netbird.grab-lab.gg → 204.168.181.110`

**Remaining manual steps (required before Stage 7b):**
- [x] Complete setup wizard at `https://netbird.grab-lab.gg/setup` — admin account created (2026-04-15)
- [x] Create setup key in Dashboard → Setup Keys (reusable, "homelab-servers" group) (2026-04-15)
- [x] Encrypt setup key into `secrets/secrets.yaml` as `netbird.setup_key` (`sops-nix path: netbird/setup_key`) via `just edit-secrets` (2026-04-15)

## Stage 7b: VPN — Homelab Client + Routes + DNS + ACLs — COMPLETE (2026-04-15)

**Files created:**
- `homelab/netbird/default.nix` — NetBird client module with `services.netbird.clients.wt0`

**Files modified:**
- `homelab/default.nix` — enabled `./netbird` import
- `machines/nixos/pebble/default.nix` — added `services.resolved` with `DNSStubListener=no`, enabled `my.services.netbird`
- `homelab/pihole/default.nix` — removed `services.resolved.enable = false` (now centralized in pebble/default.nix)
- `machines/nixos/vps/default.nix` — added coturn firewall rules (TCP/UDP 3478+5349, UDP 49152-65535)
- `machines/nixos/vps/netbird-server.nix` — fixed STUN URI scheme + TimeBasedCredentials
- `flake.nix` — added `nixpkgs-unstable` input for netbird package overlay
- `homelab/netbird/default.nix` — added `nixpkgs.overlays` to pull netbird from unstable (0.68.1)

**Configuration notes (pebble client):**
- `services.resolved` with `DNSStubListener=no` centralized in pebble/default.nix (Pattern 15)
- `services.netbird.useRoutingFeatures = "both"` enables IP forwarding for route advertisement
- `login.enable` NOT used — `netbird-wt0-login` oneshot gets SIGTERM'd during `nixos-rebuild switch` due to a race between daemon socket readiness and activation lifecycle ("Start request repeated too quickly"). One-time login done manually; credentials persist in `/var/lib/netbird-wt0/` across reboots.
- `config.ManagementURL` does NOT work in netbird 0.60.2 — crashes with "cannot unmarshal string into Go struct field Config.ManagementURL of type url.URL". Set via `--management-url` on first login.
- `sops-install-secrets.service` does NOT exist — sops-nix uses activation scripts, not a systemd unit.
- **netbird package override required** — nixos-25.11 ships 0.60.2 which is protocol-incompatible with ≥0.68.x management servers. WireGuard handshakes never complete; ICE connects then drops with "do not switch to Relay". Fixed via `nixpkgs.overlays` pulling netbird from `nixpkgs-unstable` (0.68.1). Use `lib.mkMerge` to combine the always-on overlay with the `lib.mkIf cfg.enable` conditional config block.

**Bugs fixed on VPS (machines/nixos/vps/):**
- **`services.coturn` does NOT open firewall ports** — comment in default.nix was wrong. Added `networking.firewall.allowedTCPPorts = [80 443 3478 5349]`, `allowedUDPPorts = [3478 5349]`, `allowedUDPPortRanges = [{from=49152; to=65535;}]` explicitly.
- **STUN URI missing scheme** — `"${domain}:3478"` → `"stun:${domain}:3478"` (client rejected with "unknown scheme type")
- **TimeBasedCredentials=false** — management server was issuing static credentials incompatible with coturn's `use-auth-secret`. Changed to `true` so HMAC time-based credentials are used.
- **Stale config.json** — after earlier failed deploys, `/var/lib/netbird-wt0/config.json` had a bad `ManagementURL` string from a previous iteration. Required manual `sudo rm /var/lib/netbird-wt0/config.json && sudo systemctl restart netbird-wt0`.
- **nixpkgs 25.11 netbird 0.60.2 ↔ management 0.68.3 protocol incompatibility** — `Last WireGuard handshake: -` for all peers, `Forwarding rules: 0`. ICE negotiates briefly then "ICE disconnected, do not switch to Relay. Reset priority to: None". Root cause: relay/signaling protocol changed in 0.68.x. Fixed by overlaying netbird 0.68.1 from nixpkgs-unstable.

**One-time post-deploy login (already done):**
```bash
sudo netbird-wt0 up \
  --management-url https://netbird.grab-lab.gg \
  --setup-key-file /run/secrets/netbird/setup_key
```

**Verification (all passed 2026-04-15):**
- [x] `netbird-wt0 status -d` — relays `Available`, peers `Connected`, WireGuard handshake established
- [x] `systemctl status systemd-resolved` — running; port 53 held by Pi-hole
- [x] iPhone on cellular: ping `100.102.154.38` (overlay) and `192.168.10.50` (LAN) both work
- [x] `https://grafana.grab-lab.gg` loads from cellular via VPN + route + DNS
- [x] Dashboard → Network Routes: `192.168.10.0/24` active, pebble as routing peer
- [x] Dashboard → DNS: `grab-lab.gg` match-domain → pebble overlay IP (`100.102.154.38`) port 53
- [ ] ACL policies hardened — deferred to Stage 10 (default All→All left in place)

---

## Stage 7c: Identity Provider — Kanidm — COMPLETE (verified 2026-04-16)

**Files created:**
- `homelab/kanidm/default.nix` — Kanidm module: self-signed TLS cert oneshot, server binding on `127.0.0.1:8443` + LDAPS on `127.0.0.1:636`, declarative provisioning (grabowskip person + homelab_users/homelab_admins groups + grafana OAuth2 client), sops secrets, firewall port 636

**Files modified:**
- `homelab/default.nix` — enabled `./kanidm` import, updated stage comments
- `homelab/caddy/default.nix` — added `@kanidm` virtual host for `id.grab-lab.gg` → `localhost:8443` with `tls_insecure_skip_verify`
- `homelab/grafana/default.nix` — added `"auth.generic_oauth"` OIDC block with `use_pkce = true`, `role_attribute_path` using SPN format; added `kanidm/grafana_client_secret` sops declaration with `restartUnits`
- `machines/nixos/pebble/default.nix` — added `my.services.kanidm.enable = true`

**Configuration notes:**
- **Package override required**: nixos-25.11 `services.kanidm` module defaults to `pkgs.kanidm_1_4` (EOL, removed). Must explicitly set `services.kanidm.package = pkgs.kanidmWithSecretProvisioning_1_9`. `_1_7` is also insecure/removed. Use `_1_9` (1.9.x).
- **"admin" username is reserved**: Kanidm has a built-in system account named `admin`. Provisioning a person named `admin` → 409 Conflict. Use a distinct username (`grabowskip`).
- **sops secret ownership**: provisioning `ExecStartPost` runs as the `kanidm` user. Default `root:root 0400` → permission denied. Fix: `sops.secrets."kanidm/admin_password" = { owner = "kanidm"; }` (same for `idm_admin_password`).
- **Self-signed cert must have `CA:FALSE`**: OpenSSL default self-signed certs have `CA:TRUE`. Kanidm 1.9's strict TLS rejects them (`CaUsedAsEndEntity` error). The oneshot script uses `-addext "basicConstraints=CA:FALSE"` + `-addext "subjectAltName=IP:127.0.0.1,DNS:id.<domain>"`. Also detects and regenerates old bad certs.
- **`enableClient = true` requires `clientSettings`**: module enforces this. Use `environment.systemPackages = [ pkgs.kanidmWithSecretProvisioning_1_9 ]` instead to put CLI in PATH without the constraint.
- **PKCE enforced by default**: Kanidm 1.9 requires PKCE on all OAuth2 clients. Grafana must set `use_pkce = true` in `"auth.generic_oauth"`.
- **Groups returned as SPNs**: Kanidm returns groups in the `groups` claim as full SPNs (`groupname@kanidm-domain`, e.g. `homelab_admins@id.grab-lab.gg`). Grafana `role_attribute_path` must match the full SPN: `contains(groups[*], 'homelab_admins@id.grab-lab.gg') && 'Admin' || 'Viewer'`.
- `provision.instanceUrl = "https://127.0.0.1:8443"` + `acceptInvalidCerts = true` — provisioning connects directly (not via Caddy) and accepts the self-signed cert.
- `basicSecretFile` for the Grafana OAuth2 client enables single-phase deploy — secret pre-generated in sops, shared between Kanidm provision and Grafana config.
- `kanidm/grafana_client_secret` with `mode = "0444"` — world-readable so both kanidm provisioning and grafana (`$__file{...}`) can read it.
- Port 636 (LDAPS) opened proactively for future Jellyfin integration; port 8443 NOT exposed externally.
- Pi-hole wildcard `address=/grab-lab.gg/192.168.10.50` already covers `id.grab-lab.gg` — no Pi-hole changes needed.

**Post-deploy: set person login password**
```bash
# CLI is in PATH after deploy (added via environment.systemPackages)
kanidm --url https://id.grab-lab.gg login --name idm_admin
# (password: sudo cat /run/secrets/kanidm/idm_admin_password)
kanidm --url https://id.grab-lab.gg person credential create-reset-token grabowskip
# use the printed URL to set a password via browser
```

**Verification (all passed 2026-04-16):**
- [x] `systemctl status kanidm kanidm-tls-cert` — both active
- [x] `curl -k https://127.0.0.1:8443/status` — returns JSON
- [x] `curl -sI https://id.grab-lab.gg | head -3` — HTTP 200 with valid TLS
- [x] `kanidm --url https://id.grab-lab.gg system oauth2 list --name admin` — shows `grafana` client
- [x] `https://grafana.grab-lab.gg` — "Sign in with Kanidm" button appears
- [x] Grafana OIDC round-trip completes, `grabowskip` lands with Admin role

## Stage 8: Homepage Dashboard — COMPLETE (implemented 2026-04-16)

**Files created:**
- `homelab/homepage/default.nix` — Homepage module: `services.homepage-dashboard`, port 3010, services/bookmarks config

**Files modified:**
- `homelab/default.nix` — enabled `./homepage` import
- `homelab/caddy/default.nix` — added `@home` virtual host for `home.grab-lab.gg`
- `machines/nixos/pebble/default.nix` — `my.services.homepage.enable = true`

**Configuration notes:**
- Native `services.homepage-dashboard` module (homepage-dashboard 1.7.0 in nixos-25.11)
- Port 3010 (remapped from default 3000 to avoid Grafana conflict)
- `allowedHosts = "home.grab-lab.gg"` required for reverse-proxy access — without it homepage returns a 403
- Services grouped into four sections: Infrastructure (Pi-hole, Caddy), Security (Vaultwarden, Kanidm), Monitoring (Grafana, Prometheus), Networking (NetBird)
- Auth: Homepage has no native auth. Caddy `forward_auth` via Kanidm (Pattern 22) can be added once the endpoint is verified — see `⚠️ VERIFY` note in `docs/NIX-PATTERNS.md Pattern 22`. Deferred.
- Pi-hole wildcard `address=/grab-lab.gg/192.168.10.50` already covers `home.grab-lab.gg` — no Pi-hole changes needed

**Verification (all passed 2026-04-17):**
- [x] `systemctl status homepage-dashboard` — active
- [x] `https://home.grab-lab.gg` loads dashboard with valid TLS
- [x] Four service groups visible: Infrastructure, Security, Monitoring, Networking
- [x] Clicking service links opens correct URLs

## Stage 9a: Services (Mosquitto + HACS + Home Assistant + Uptime Kuma) — COMPLETE (verified 2026-04-18)

**Files created:**
- `homelab/mosquitto/default.nix` — Mosquitto module: `services.mosquitto`, port 1883, `homeassistant` user with readwrite ACL
- `homelab/home-assistant/default.nix` — HA module: Podman OCI container, `--network=host`, `--privileged`, HACS oneshot (Pattern 11 Approach A), activation script for initial `configuration.yaml`
- `homelab/uptime-kuma/default.nix` — Uptime Kuma module: `services.uptime-kuma`, port 3001 on 127.0.0.1

**Files modified:**
- `homelab/default.nix` — enabled `./mosquitto`, `./home-assistant`, `./uptime-kuma` imports
- `homelab/caddy/default.nix` — added `@ha` (ha.grab-lab.gg → 8123) and `@uptime` (uptime.grab-lab.gg → 3001) virtual hosts
- `homelab/homepage/default.nix` — added Uptime Kuma to Monitoring group; new "Home Automation" group with Home Assistant
- `machines/nixos/pebble/default.nix` — enabled mosquitto, homeAssistant, uptimeKuma services

**Configuration notes:**
- Mosquitto: native `services.mosquitto`; per-listener password auth (NixOS module enforces `per_listener_settings = true`). Pre-hashed passwords inline in config — generate with `mosquitto_passwd`, replace `REPLACE_ME` placeholder before first deploy.
- Home Assistant: `ghcr.io/home-assistant/home-assistant:stable` OCI image. Volumes: `/var/lib/homeassistant:/config`, `/etc/localtime`. Activation script writes minimal `configuration.yaml` (with Caddy trusted proxy config) only on first deploy — does not overwrite on subsequent rebuilds.
- HACS: `systemd.services.hacs-install` oneshot runs before `podman-homeassistant.service`. Downloads latest HACS zip from GitHub, idempotent. Requires completing GitHub OAuth device flow in HA UI after first boot.
- Uptime Kuma: native `services.uptime-kuma`, binds to 127.0.0.1:3001, proxied via Caddy. No sops secrets needed; internal auth handles login.
- HA → Mosquitto soft ordering: `wants/after = ["mosquitto.service"]` on `podman-homeassistant.service` — HA works without MQTT but prefers it to be up first.

**Pre-deploy action required:**
```bash
# Generate Mosquitto password hash for the homeassistant user:
nix shell nixpkgs#mosquitto --command mosquitto_passwd -c /tmp/p homeassistant
# Paste the hash (everything after "homeassistant:") into homelab/mosquitto/default.nix
# replacing the REPLACE_ME placeholder
```

**Post-deploy steps (manual, in order):**
1. `https://ha.grab-lab.gg` — complete Home Assistant onboarding wizard
2. Settings → Devices & Services → Add Integration → HACS → complete GitHub OAuth device flow
3. Settings → Devices & Services → Add Integration → MQTT → server `127.0.0.1`, port `1883`, user `homeassistant`, password set via mosquitto_passwd
4. Settings → Devices & Services → Add Integration → UniFi Network → requires **local admin** account on controller (not SSO/cloud account)
5. `https://uptime.grab-lab.gg` — create Uptime Kuma admin account on first visit

**Configuration gotchas (discovered during deploy):**
- Caddy must use `127.0.0.1:8123` not `localhost:8123` — on dual-stack systems `localhost` resolves to `::1`, which HA rejects as an untrusted proxy even when `::1` is listed in `trusted_proxies`
- After restoring a backup, `configuration.yaml` loses the `http:` block — activation script now detects and re-injects it if `^http:` is absent
- `sudo podman ps` required — Podman runs rootful, container not visible without sudo

**Verification (all passed 2026-04-18):**
- [x] `systemctl status mosquitto` — active
- [x] `sudo podman ps` — shows `homeassistant` container running
- [x] `sudo test -f /var/lib/homeassistant/custom_components/hacs/__init__.py` — HACS present
- [x] `https://ha.grab-lab.gg` loads Home Assistant
- [x] `https://uptime.grab-lab.gg` loads Uptime Kuma
- [x] HA MQTT integration connects to `127.0.0.1:1883`

## Stage 9b: Services (Voice Pipeline + ESPHome + Matter Server) — COMPLETE (implemented 2026-04-18)

**Files created:**
- `homelab/wyoming/default.nix` — Wyoming voice pipeline: Faster-Whisper STT (port 10300), Piper TTS (port 10200), OpenWakeWord (port 10400); native NixOS modules
- `homelab/matter-server/default.nix` — Matter Server OCI container: `--network=host`, D-Bus mount, Avahi ordering, IPv6 enabled, IPv6 forwarding disabled

**Files modified:**
- `homelab/home-assistant/default.nix` — added ESPHome OCI container (`--network=host`, port 6052) as `my.services.homeAssistant.esphome.*` sub-option; added Avahi mDNS service configuration
- `homelab/default.nix` — added `./wyoming` and `./matter-server` imports
- `homelab/caddy/default.nix` — added `@esphome` virtual host (esphome.grab-lab.gg → port 6052)
- `homelab/homepage/default.nix` — added ESPHome to "Home Automation" service group
- `machines/nixos/pebble/default.nix` — enabled `my.services.wyoming`, `my.services.matterServer`, `my.services.homeAssistant.esphome`

**Configuration notes:**
- Wyoming: all three services native NixOS modules; `lib.mkForce "all"` ProcSubset override kept as documentation (nixos-25.11 already ships the fix from PR #372898)
- OpenWakeWord: `preloadModels` was removed in wyoming-openwakeword v2.0.0 — built-in models load automatically; do not set this option in nixos-25.11
- ESPHome: OCI container (`ghcr.io/esphome/esphome:2026.3.1`) — native `services.esphome` has three unresolved bugs (DynamicUser path, missing pyserial, missing font component)
- Matter Server: OCI container (`ghcr.io/home-assistant-libs/python-matter-server:stable`) — CHIP SDK not buildable natively; `--security-opt=label=disable` required for Bluetooth/D-Bus; `boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkDefault 0` prevents 30-minute reachability outages
- Avahi (`services.avahi.openFirewall = true`) added to home-assistant module — used by ESPHome and Matter Server for mDNS device discovery
- ESPHome and Matter Server: `systemd.services.podman-*.wants/after = ["avahi-daemon.service"]` (Pattern 16C)
- ESPHome options co-located as sub-options of `my.services.homeAssistant.esphome.*` per STRUCTURE.md
- lib.mkMerge pattern used in home-assistant/default.nix (same as netbird module, Pattern 14)

**Post-deploy steps (manual, in order):**
1. `systemctl status wyoming-faster-whisper-main wyoming-piper-main wyoming-openwakeword` — verify all three active
2. `sudo podman ps` — verify `esphome` and `matter-server` containers running
3. HA → Settings → Voice assistants → create pipeline: Whisper (localhost:10300), Piper (localhost:10200), OpenWakeWord (localhost:10400)
4. HA → Settings → Devices & Services → ESPHome → Add Integration → host `127.0.0.1`, port `6052`
5. HA → Settings → Devices & Services → Matter → Add Integration → `ws://127.0.0.1:5580/ws`
6. `https://esphome.grab-lab.gg` loads ESPHome dashboard with valid TLS

**Verification (verified 2026-04-18):**
- [x] `systemctl status wyoming-faster-whisper-main wyoming-piper-main wyoming-openwakeword` — all active
- [x] `sudo podman ps` — shows `esphome` and `matter-server` containers running
- [x] HA voice assistant: hold mic button in mobile app, speak a command — HA responds with TTS
- [x] `https://esphome.grab-lab.gg` loads ESPHome dashboard; ESP devices discovered
- [x] Matter integration configured at `ws://127.0.0.1:5580/ws`

## Stage 10: Hardening, Backups, VPS Log Shipping — COMPLETE (implemented 2026-04-19)

**Files created:**
- `machines/nixos/vps/monitoring.nix` — Alloy collects VPS journald logs, pushes to pebble Loki (100.102.154.38:3100) over NetBird mesh
- `homelab/backup/default.nix` — Sanoid ZFS snapshots (zroot/var + zroot/home), Syncoid SSH replication to NAS, Restic daily Vaultwarden backup to NAS SFTP
- `machines/nixos/_common/security.nix` — fail2ban SSH jail on all machines (pebble + VPS)

**Files modified:**
- `machines/nixos/vps/default.nix` — added `./monitoring.nix` import
- `homelab/loki/default.nix` — changed `http_listen_address` from `127.0.0.1` to `0.0.0.0`; replaced EOL Promtail with Alloy for pebble journald shipping
- `machines/nixos/pebble/default.nix` — added `networking.firewall.interfaces."wt0".allowedTCPPorts = [ 3100 ]`; enabled `my.services.backup`
- `homelab/default.nix` — enabled `./backup` import
- `machines/nixos/_common/default.nix` — added `./security.nix` import

**Configuration notes:**
- **VPS log shipping**: Alloy on VPS pushes to pebble Loki via NetBird mesh (encrypted, no public exposure). Port 3100 opened on wt0 interface only — stays closed on eth0.
- **Promtail → Alloy**: Promtail is EOL (2026-03-02). Both pebble and VPS now use Alloy (`services.alloy`). Labels: `{host="pebble"}` and `{host="vps"}` for filtering in Grafana.
- **Sanoid**: hourly 24, daily 7, weekly 4, monthly 3 snapshots for `zroot/var` and `zroot/home`.
- **Syncoid SSH key**: generate `/root/.ssh/syncoid_ed25519` on pebble, add pubkey to NAS. See `homelab/backup/default.nix` comment.
- **NAS placeholders**: `nasUser`, `nasIP`, `nasPool` in `homelab/backup/default.nix` must be filled in before first deploy.
- **Restic secret**: add `restic/password: <password>` to `secrets/secrets.yaml` via `just edit-secrets`.
- **Fail2ban**: `services.fail2ban` in `_common/security.nix` applies to all machines (pebble + VPS). maxretry=5 global, maxretry=3 for sshd jail, bantime=10m.
- **deploy-rs**: was already complete from earlier stages. `just deploy pebble` and `just deploy-vps` both functional.
- **NetBird ACLs**: manual step in NetBird Dashboard — delete default "All→All" policy, add group-scoped policies. Not declaratively codified (dashboard-only).
- **VPS SSH IP restriction**: skipped (dynamic admin IP). Fail2ban + key-only auth provides SSH protection.

**Pre-deploy actions required:**
```bash
# On pebble (as root):
sudo ssh-keygen -t ed25519 -f /root/.ssh/syncoid_ed25519 -N "" -C "syncoid@pebble"
sudo cat /root/.ssh/syncoid_ed25519.pub  # add to NAS authorized_keys

# Fill in NAS details in homelab/backup/default.nix:
#   nasUser = "your-nas-user";
#   nasIP   = "192.168.10.X";
#   nasPool = "your-pool-name";
#   NAS must have: tank/pebble/var, tank/pebble/home (syncoid), /tank/backups/restic/vaultwarden/ (restic)

# Add restic password to secrets:
just edit-secrets
# Add: restic/password: "your-strong-password"
```

**Verification:**
- [x] `just deploy pebble` — Loki, Alloy, backup, firewall changes applied
- [x] `just deploy-vps` — Alloy shipping VPS logs
- [ ] `systemctl status alloy` on pebble — Alloy active, shipping pebble journald
- [ ] `ssh admin@204.168.181.110 systemctl status alloy` — Alloy active on VPS
- [ ] Grafana → Explore → Loki → `{host="pebble"}` returns pebble logs
- [ ] Grafana → Explore → Loki → `{host="vps"}` returns VPS journald logs
- [ ] `zfs list -t snapshot` shows `auto_` snapshots from Sanoid (after deploy)
- [ ] `systemctl status fail2ban` on pebble and VPS — both active
- [ ] `fail2ban-client status sshd` — sshd jail enabled
- [ ] NetBird Dashboard: default "All→All" ACL deleted; group-scoped policies added (manual)

## Phase 2: Machine 2 (boulder) — NOT STARTED
See docs/STAGES.md for Stages 11-18

---

## Open TODOs

### VPS log shipping to Loki — IMPLEMENTED (Stage 10, 2026-04-19)

`machines/nixos/vps/monitoring.nix` ships VPS journald logs via Alloy → NetBird mesh → pebble Loki.
Filter in Grafana: `{host="vps", job="systemd-journal"}`.
See Stage 10 notes above and `docs/VPS-LOKI-SHIPPING.md` for full design rationale.

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

### VPS Log Shipping Research — 2026-04-16

Researched how to ship VPS logs to Loki. Findings documented and incorporated:

**docs/VPS-LOKI-SHIPPING.md** — new, primary reference (implementation plan + safety analysis)

**docs/SERVICE-CONFIGS.md** changes:
- Loki entry: added compactor `delete_request_store` gotcha (verified in Stage 6)
- Loki entry: **Promtail marked EOL** (2026-03-02), replaced with `services.alloy` as recommended shipper
- Loki entry: added multi-machine shipping section with TODO and reference to VPS-LOKI-SHIPPING.md
- Loki entry: added Alloy single-machine config example (River syntax)
- Service verification table: added Alloy row

**docs/STAGES.md** changes:
- Stage 10: added TODO for VPS log shipping; added verification step for `{host="vps"}` in Loki

**PROGRESS.md** (this file):
- Added "Open TODOs" section with VPS log shipping task

**Key decisions recorded:**
- Promtail is EOL — do not create new promtail instances; use `services.alloy`
- VPS log shipping via Alloy over NetBird mesh (not public Loki exposure)
- Loki needs `http_listen_address = "0.0.0.0"` + `networking.firewall.interfaces."wt0".allowedTCPPorts = [3100]` on pebble to receive remote pushes safely
- pebble's NetBird IP is `100.102.154.38` (from Stage 7b verification)

---

### IdP Strategy + NetBird OCI Migration — 2026-04-15

**Decision 1: NetBird server via OCI containers, not native NixOS module**
- `services.netbird.server` exists in nixpkgs but is not production-ready as of nixos-25.11
- Configuration failures during testing: unclear option interactions, sparse documentation, complex OIDC chicken-and-egg startup ordering
- Switched to `virtualisation.oci-containers` on NixOS VPS — same container images the official Docker Compose setup uses, but managed declaratively by NixOS
- Native NixOS Caddy replaces nginx for TLS termination (same module as pebble, consistent pattern)
- Documented in: docs/ARCHITECTURE.md (isolation table), docs/SERVICE-CONFIGS.md, docs/NIX-PATTERNS.md (Patterns 19–20), docs/STAGES.md (Stage 7a), docs/NETBIRD-SELFHOSTED.md

**Decision 2: Embedded Dex for NetBird auth + Kanidm on homelab for all service SSO**
- **Tier 1 — VPS:** NetBird's embedded Dex (built into `netbirdio/management:latest` since v0.62.0) handles VPN authentication only. Zero configuration, zero extra RAM. Eliminates Zitadel Cloud dependency.
- **Tier 2 — pebble:** Kanidm (`services.kanidm`) handles all homelab service SSO (OIDC + LDAP). ~50–80 MB RAM. Native NixOS module with declarative OAuth2 client provisioning.
- **Why two tiers:** Chicken-and-egg — need VPN to reach homelab IdP, but need IdP to authenticate VPN. Embedded Dex on VPS breaks the deadlock.
- **New Stage 7c:** Kanidm deployment added to STAGES.md (after 7b, before Stage 8; blocks Outline/Immich/etc.)
- Documented in: docs/IDP-STRATEGY.md (new), docs/ARCHITECTURE.md (Identity & Authentication section), docs/SERVICE-CONFIGS.md (Kanidm entry + auth notes per service), docs/NIX-PATTERNS.md (Patterns 21–23), docs/STAGES.md (Stage 7c), docs/STRUCTURE.md (kanidm/ module)
