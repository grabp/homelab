# ARCHITECTURE.md — Architecture Decisions

## ZFS on a single SSD delivers snapshots, compression, and integrity without redundancy

**Recommendation: ZFS with disko.** Even on a single disk, ZFS provides **checksumming** (catches bit rot and silent corruption), **LZ4 compression** (saves space and actually improves SSD I/O by reducing write volume), and **instant snapshots** (enabling atomic backups via `zfs send` and ephemeral-root rollback). The notthebee/nix-config reference project uses exactly this pattern — ZFS via disko on single disks across all servers.

The **16 GB RAM concern is manageable**. ZFS's ARC (Adaptive Replacement Cache) is a *cache*, not a reservation — it releases memory under pressure. Cap ARC at 4 GB with `boot.kernelParams = [ "zfs.zfs_arc_max=4294967296" ];`, leaving ~12 GB for services. Without deduplication (which you should never enable on a homelab), 16 GB is comfortably sufficient.

ext4 is simpler but offers no snapshots, no checksumming, and no compression — limiting for a homelab wanting rollback and backup capabilities. btrfs offers similar features to ZFS but NixOS's ZFS integration is more mature and better documented.

**Critical ZFS configuration for NixOS:**

```nix
boot.supportedFilesystems = [ "zfs" ];
boot.zfs.forceImportRoot = false;
networking.hostId = "<generate: head -c4 /dev/urandom | od -A none -t x4>";
services.zfs.autoScrub.enable = true;
services.zfs.trim.enable = true;
boot.kernelParams = [ "nohibernate" "zfs.zfs_arc_max=4294967296" ];
```

**Gotchas:** ZFS often lags the latest kernel — use the NixOS default LTS kernel. ZFS does not support swap files (use a separate swap partition). Never fill the pool beyond **80%** — create a reserved dataset with `refreservation=10G`. Use `legacy` mountpoints in disko so NixOS manages mounts via `fileSystems`. Set `ashift=12` for SSD alignment.

## Hybrid isolation: native NixOS modules plus Podman for services without modules

**Recommendation: Native NixOS modules for most services, Podman OCI containers for Pi-hole and optionally Home Assistant.** This is the community-standard pattern and what notthebee uses.

**Native NixOS modules** provide first-class integration: declarative configuration, automatic user/group creation, systemd sandboxing (`DynamicUser`, `ProtectHome`, `PrivateTmp`), and seamless secrets injection via sops-nix. They are the right choice for every service that has a well-maintained NixOS module.

**Podman OCI containers** (via `virtualisation.oci-containers`) provide true filesystem/network isolation and access to upstream Docker images. They are essential for **Pi-hole** (no NixOS module exists) and recommended for **Home Assistant** (upstream considers NixOS unsupported; HA version freezes at NixOS branch-off and misses security patches).

| Service | Isolation | Rationale |
|---------|-----------|-----------|
| Caddy | Native | Excellent module, reverse proxy needs host network |
| Prometheus | Native | Mature module with extensive exporter ecosystem |
| Grafana | Native | Well-maintained module with declarative provisioning |
| Loki | Native | Solid module, simple config |
| Homepage | Native | Module exists with structured config |
| Uptime Kuma | Native | Module exists, simple service |
| NetBird client (pebble) | Native | `services.netbird.clients.wt0` — routing peer, connects to self-hosted control plane on VPS |
| **NetBird server (VPS)** | **Podman OCI containers** | VPS runs NixOS; NetBird stack runs as OCI containers via `virtualisation.oci-containers`. `services.netbird.server` NixOS module exists but is not production-ready as of nixos-25.11 — use OCI containers instead |
| **Kanidm** | **Native** | `services.kanidm` — OIDC + LDAP IdP for all homelab service SSO; runs on pebble, accessible via VPN only |
| **Pi-hole** | **Podman** | No NixOS module — must use OCI |
| **Home Assistant** | **Podman** | Complex ecosystem, frequent updates, plugin dependencies, upstream unsupported on NixOS |
| Mosquitto | Native | Mature module; `per_listener_settings true` behavior; latency-sensitive MQTT |
| Wyoming Whisper | Native | Good module; **apply ProcSubset fix** or inference is ~7× slower (see note below) |
| Wyoming Piper | Native | Well-maintained; no known bugs |
| Wyoming OpenWakeWord | Native | Very lightweight; verify model name against package version |
| **ESPHome** | **Podman** | Three unresolved native bugs: DynamicUser path, pyserial missing, font component |
| **Matter Server** | **Podman** | CHIP SDK requires pre-built binary wheels; intractable to build natively |
| Vaultwarden | Native | `services.vaultwarden` module; ~50 MB RAM; critical service stays on pebble |

⚠️ **Native module gotcha — faster-whisper `ProcSubset` (nixpkgs PR #372898):** The systemd hardening sets `ProcSubset=pid`, which blocks CTranslate2 from reading `/proc/cpuinfo` and forces a slow fallback code path. A 3-second audio clip takes ~20 s instead of ~3 s. Always override in the machine config:
```nix
systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset = lib.mkForce "all";
```

**Podman setup:**
```nix
virtualisation.podman = {
  enable = true;
  dockerCompat = true;
  defaultNetwork.settings.dns_enabled = true;
  autoPrune.enable = true;
};
```

**Gotchas:** Podman rootless on ZFS requires `acltype=posixacl` on underlying datasets. Home Assistant, ESPHome, and Matter Server all use `--network=host` for mDNS and IPv6 multicast device discovery — they share the host network namespace and communicate with native Wyoming/Mosquitto services over `localhost`. Container volumes must reside on persistent ZFS datasets.

## Network architecture: localhost binding with Caddy as the single entry point

All services bind to `127.0.0.1:<port>`. Caddy listens on `0.0.0.0:80/443` and reverse-proxies by subdomain. This eliminates bridge networks, container IP management, and NAT complexity entirely.

```
Internet → (blocked, no port forwards to homelab — CGNAT)

LAN clients → Pi-hole (DNS :53) → resolves *.grab-lab.gg → 192.168.10.X
                                 → Caddy (:443) → localhost:<service-port>

VPN peers (phone/laptop)
  → TCP 443 / UDP 3478 → VPS (netbird.grab-lab.gg, public IP)
      ↕ relay or P2P WireGuard (encrypted end-to-end)
  ← pebble (behind CGNAT, outbound-only to VPS)
  → NetBird DNS: *.grab-lab.gg match-domain → Pi-hole overlay IP → Caddy → service

pebble ← ISP CGNAT (symmetric NAT, no inbound) ← VPS relay ← VPN peer
         (P2P hole-punch if CGNAT maps consistently; relay otherwise ~7 Mbps / ~85ms)
```

The host gets a static IP on `192.168.10.0/24`. DNS flows: LAN clients → Pi-hole → upstream. Pi-hole resolves `*.grab-lab.gg` to Caddy's IP internally using a dnsmasq wildcard (`address=/grab-lab.gg/192.168.10.X`). Public DNS returns NXDOMAIN since no A records exist in Cloudflare.

**Port assignments (conflict-free):**

| Service | Port | Notes |
|---------|------|-------|
| Pi-hole DNS | 53 | Bind to host IP |
| Pi-hole Web UI | 8089 | Remapped from 80 (Caddy needs 80) |
| Caddy | 80, 443 | Reverse proxy entry |
| Prometheus | 9090 | No conflict |
| Grafana | 3000 | — |
| Loki | 3100 | — |
| Home Assistant | 8123 | — |
| Uptime Kuma | 3001 | — |
| Homepage | 3010 | Remapped from 3000 to avoid Grafana conflict |
| NetBird | 51821 | WireGuard UDP |
| Mosquitto | 1883 | MQTT broker |
| Wyoming Whisper | 10300 | Speech-to-text (Wyoming protocol) |
| Wyoming Piper | 10200 | Text-to-speech (Wyoming protocol) |
| Wyoming OpenWakeWord | 10400 | Wake word detection (Wyoming protocol) |
| ESPHome | 6052 | ESP device dashboard |
| Matter Server | 5580 | Matter WebSocket API |
| Vaultwarden | 8222 | Password manager (Bitwarden-compatible) |

**mDNS and host networking:** ESPHome, Matter Server, and Home Assistant use `--network=host` in their Podman containers, giving them direct access to the host network stack for mDNS and IPv6 multicast. Enable Avahi on the host for `.local` resolution and ESPHome device discovery:

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;  # Use nssmdns4 (not nssmdns) — avoids slow lookups for non-.local domains
  publish = { enable = true; addresses = true; };
};
```

⚠️ IPv6 forwarding must be **disabled** when running Matter Server (`boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 0`) — if enabled, Matter devices experience up to 30-minute reachability outages on network changes.

## VPS control plane: two-machine architecture for self-hosted NetBird behind CGNAT

This flake manages **two machines**: `pebble` (homelab behind CGNAT) and `vps` (Hetzner VPS, public IP, running the NetBird control plane). The homelab has no public IP and cannot receive inbound connections — the VPS is the only externally reachable endpoint.

**Recommendation: Hetzner CX22 at €3.79/month.** 4 GB RAM / 2 vCPU / 20 TB bandwidth. The NetBird stack (4 containers since v0.62.0) uses ~300–500 MB idle RAM. Real-world reports show 0.12 load average after months of production use. The ARM variant (CAX11) works identically — NetBird images are multi-arch.

See `docs/NETBIRD-SELFHOSTED.md` for the full provider comparison and migration strategy.

### CGNAT implications

The homelab's ISP uses symmetric NAT (Endpoint-Dependent Mapping). STUN hole-punching fails virtually 100% of the time, so VPN peers almost always relay through the VPS via WireGuard. Relay performance: **~7 Mbps throughput, ~85ms latency** — adequate for dashboards and media at moderate quality. The VPS never decrypts traffic; WireGuard provides end-to-end encryption between peers.

**Known issue (stale relay, GitHub #3936):** Behind CGNAT, NetBird can show "Connected" but stop passing traffic. Workaround: `netbird-wt0 down && netbird-wt0 up` or restart the systemd service. Consider a monitoring timer.

### VPS ports required

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | HTTP redirect + ACME challenges |
| 443 | TCP | Management API, Signal (gRPC/HTTP2), Dashboard, Relay WebSocket |
| 3478 | UDP | STUN/TURN (Coturn) |
| 49152–65535 | UDP | TURN relay ephemeral range |
| 22 | TCP | SSH (restrict to your IP) |

⚠️ **Hetzner firewall**: uses stateless rules — also open the ephemeral UDP range from `/proc/sys/net/ipv4/ip_local_port_range` for TURN return traffic.

### DNS records

One A record: `netbird.grab-lab.gg → <VPS_PUBLIC_IP>`. Set it to **DNS only** in Cloudflare (gray cloud) — Cloudflare's HTTP proxy breaks gRPC.

### TLS termination

We use native NixOS Caddy (`services.caddy`) on the VPS for TLS termination — not Traefik or a Caddy container. Native Caddy handles Let's Encrypt via HTTP-01 challenge and avoids container overhead.

### Split DNS via NetBird match-domain nameserver

VPN clients resolve `*.grab-lab.gg` through Pi-hole via a NetBird nameserver group:

- Dashboard → DNS → Nameservers → Add: IP = Pi-hole overlay IP (e.g. `100.x.y.z`), Match domain = `grab-lab.gg`
- Add fallback nameserver: `1.1.1.1` / `8.8.8.8` with no match domain

Pi-hole returns Caddy's LAN IP; traffic routes through the NetBird routing peer to the service. Alternative: NetBird Custom DNS Zones (v0.63+) — add A records directly in the dashboard without Pi-hole in the chain (loses ad-blocking).

### systemd-resolved + Pi-hole coexistence (`DNSStubListener=no`)

NetBird requires `systemd-resolved` to register match-domain nameservers via `resolvectl`. Pi-hole needs port 53. Solution: **disable the stub listener only**:

```nix
services.resolved = {
  enable = true;
  extraConfig = ''
    DNSStubListener=no
  '';
};
```

`systemd-resolved` continues running as a DNS routing daemon for NetBird's `resolvectl` calls, but frees port 53 for Pi-hole. NixOS sets `/etc/resolv.conf` to point at Pi-hole's IP automatically.

### Security model: VPS compromise

The VPS never sees decrypted traffic — WireGuard keys never leave the endpoints. If the VPS is compromised, an attacker **can**: see peer metadata (hostnames, public keys, connection times), add rogue peers via setup keys, modify ACLs, and disrupt service. They **cannot**: decrypt peer traffic, perform MITM, or access services directly.

**Harden ACLs** — delete the default "All → All" policy and replace with explicit policies:
```
homelab-servers ↔ homelab-servers  (any protocol)
personal-devices → homelab-servers (TCP 80, 443)
admin-devices → homelab-servers    (TCP 22, 80, 443)
all-peers → pihole                 (UDP 53)
```

**Setup key hygiene**: reusable key for servers (assign to group), one-off keys for personal devices with 24–72 h expiration. Revoke after enrollment.

## sops-nix with age backend provides the best balance of flexibility and simplicity

**Recommendation: sops-nix** (`github:Mic92/sops-nix`) with the age encryption backend.

Both sops-nix and agenix are battle-tested. The decisive advantages of sops-nix for this homelab are: **multiple secrets per file** (one YAML file instead of dozens of `.age` files), **template support** (embed secrets into config files like Home Assistant's `secrets.yaml`), and **future flexibility** (sops supports cloud KMS if you ever add CI/CD). The age backend keeps the operational simplicity of agenix — derive age keys from SSH host keys via `ssh-to-age`, same workflow.

| Feature | agenix | sops-nix |
|---------|--------|----------|
| Encryption | age only | age, GPG, cloud KMS |
| File format | One secret per `.age` file | Multiple secrets per YAML/JSON |
| Templates | No | Yes |
| Key management | `secrets.nix` | `.sops.yaml` |
| Decryption path | `/run/agenix/` | `/run/secrets/` |

If absolute simplicity is the priority, agenix is harder to misconfigure. The reference project (notthebee) uses agenix; the user's previous repo (grabp/lab) uses sops-nix. Either works — pick one and commit.

**Critical gotcha:** Neither tool provides secrets at Nix evaluation time — only at activation. SSH host keys **must be persisted** across reboots (they are the decryption identity). After reinstall: `ssh-keyscan`, add to `.sops.yaml`, rekey all secrets.

## Ephemeral root via ZFS dataset separation, not the full impermanence module

**Recommendation: Use ZFS dataset separation (notthebee's approach), not the `nix-community/impermanence` module.** Create a root dataset (`zroot/root`) rolled back to an empty snapshot each boot, with **separate persistent datasets** for `/var/lib`, `/var/log`, `/nix`, `/home`, and `/etc/nixos`.

This gives you ephemeral root benefits — clean system, no configuration drift in `/tmp`, `/root`, `/etc` cruft — **without** the impermanence module's per-file/directory bind-mount declarations. Since `/var/lib` is fully persisted as a ZFS dataset, all service state (databases, Home Assistant, container volumes) survives reboots without individual declarations. This is **dramatically simpler** for a stateful homelab and provides 80% of the benefit.

Full impermanence (with the module) requires explicitly declaring every path that should persist. Missing one path means **data loss on reboot**. For a homelab with many stateful services, this is error-prone and time-consuming to maintain.

**Must persist regardless of approach:** `/etc/ssh` (host keys for secrets decryption), `/etc/machine-id` (systemd identity), `/var/lib` (all service state).

## Three-tier backup strategy protects against data loss on single-disk hardware

On NixOS, the system configuration lives in git and is fully reproducible — **never back up `/nix/store`**. Back up only: application state in `/var/lib`, SSH host keys, and secrets identity files.

**Tier 1 — ZFS auto-snapshots** via `services.sanoid`: Hourly snapshots (keep 24), daily (keep 30), monthly (keep 6). Instant local rollback for "oops" moments.

**Tier 2 — ZFS replication to NAS** via `services.syncoid`: Nightly incremental `zfs send` to NAS. Fast, space-efficient, local redundancy against SSD failure.

**Tier 3 — Restic to NAS** (and optionally cloud): Nightly file-level backup from a consistent ZFS snapshot. Provides deduplication, encryption, retention policies, and granular restore.

```nix
services.sanoid = {
  enable = true;
  datasets."zroot/var" = {
    hourly = 24; daily = 30; monthly = 6;
    autosnap = true;
  };
};

services.restic.backups.homelab = {
  initialize = true;
  paths = [ "/var/lib" ];
  repository = "/mnt/nas/backup/restic/homelab";
  passwordFile = config.sops.secrets.restic-password.path;
  timerConfig = { OnCalendar = "02:30"; };
  pruneOpts = [ "--keep-daily 7" "--keep-weekly 5" "--keep-monthly 12" ];
};
```

**Gotcha:** Never back up SQLite databases (used by Home Assistant, Grafana, Pi-hole) without first snapshotting or stopping the service — risk of corruption. ZFS snapshots provide atomic consistency.

## UniFi DHCP + Pi-hole DNS: let UniFi handle DHCP, Pi-hole handles DNS only

**Best practice: UniFi manages DHCP, Pi-hole is the DNS server.** In the UniFi controller: Settings → Networks → [Network] → DHCP → set DNS Server 1 to Pi-hole's IP (`192.168.10.X`). **Leave DNS Server 2 blank** — a public fallback would bypass Pi-hole entirely.

Enable Pi-hole's **conditional forwarding** (Settings → DNS → Conditional Forwarding) pointed at the UniFi gateway (`192.168.10.1`) so Pi-hole resolves device hostnames from DHCP leases.

The NixOS server itself uses a static IP (configured in NixOS, not DHCP) with `networking.nameservers = [ "127.0.0.1" ]` so it resolves via its own Pi-hole instance.

## Unified backup strategy across all machines

This flake manages multiple machines. Each follows the same three-tier backup approach, with service-specific handling.

### What to back up (per machine)

**Never back up:**
- `/nix/store` — fully reproducible from flake
- Container images — re-pulled on deployment
- Generated caches — Jellyfin metadata, Immich thumbnails, search indices

**Always back up:**
- `/var/lib/*` — all service state (databases, configs, uploads)
- `/etc/ssh/ssh_host_*` — host keys (decryption identity for sops)
- `/etc/machine-id` — systemd identity
- `~/.config/sops/age/keys.txt` (on admin workstation) — admin decryption key

### Machine-specific backup targets

| Machine | Sanoid datasets | Restic paths | NAS target |
|---------|----------------|--------------|------------|
| pebble | `zroot/var` | `/var/lib` | `/mnt/nas/backup/pebble` |
| boulder | `zroot/var` | `/var/lib` | `/mnt/nas/backup/boulder` |
| vps | (no ZFS) | `/var/lib` | Off-site (⚠️ VERIFY: Hetzner backup or rsync to NAS) |

### Service-specific backup handling

| Service | Special handling | Notes |
|---------|-----------------|-------|
| **Vaultwarden** | `services.vaultwarden.backupDir` creates automatic daily SQLite backups; include this dir in restic | Critical — loss means credential recovery via emergency sheets only |
| **Immich** | PostgreSQL dump before snapshot; photos already on NAS | Don't backup thumbnails (`/var/lib/immich/thumbs`) |
| **Paperless-ngx** | PostgreSQL dump; documents already on NAS | Index can be rebuilt |
| **Home Assistant** | ZFS snapshot sufficient (SQLite + YAML) | `.db-wal` and `.db-shm` included in atomic snapshot |
| **Grafana** | ZFS snapshot sufficient (SQLite) | Dashboards can be re-provisioned |
| **PostgreSQL (shared)** | `pg_dumpall` before ZFS snapshot | Single dump covers Outline, Vikunja, Paperless |

### Bare metal recovery procedure

1. **Provision new hardware** — boot NixOS ISO, run disko
2. **Clone flake** — `git clone` from GitHub/GitLab
3. **Restore admin age key** — copy `~/.config/sops/age/keys.txt` from secure backup
4. **Generate new host key** — new machine gets new SSH host key
5. **Update .sops.yaml** — add new host's age key, rekey all secrets
6. **Deploy** — `nixos-rebuild switch --flake .#<hostname>`
7. **Restore /var/lib** — restic restore from NAS
8. **Verify services** — check logs, test functionality

**Recovery keys to store offline:**
- `.sops.yaml` (which age keys can decrypt which secrets)
- Admin age private key (paper or encrypted USB)
- Vaultwarden emergency sheet (2FA recovery)

### What backs up the NAS?

The NAS (TrueNAS) is the backup destination, not a managed NixOS machine. Its backup strategy is out of scope for this flake but should include:
- ZFS replication to second pool or off-site
- Cloud backup for critical data (photos, documents)
- ⚠️ NOTE: If NAS fails, homelab service state is recoverable but bulk media is not

## Unified storage strategy

### Local SSD vs NAS decision matrix

| Data type | Location | Rationale |
|-----------|----------|-----------|
| Service databases (SQLite, PostgreSQL) | Local SSD | Latency-sensitive, transaction-heavy |
| Container layers/images | Local SSD | I/O intensive during pulls |
| Transcoding temp files | Local SSD | High-bandwidth temporary storage |
| Photo originals (Immich) | NAS | Large, already organized on NAS |
| Media library (Jellyfin) | NAS | Large, shared with other devices |
| Document archive (Paperless) | NAS | Searchable from multiple machines |
| Backups | NAS | Centralized, redundant storage |

### ZFS dataset layout

**pebble (machine 1):**
```
zroot
├── root          # Ephemeral (optional rollback)
├── nix           # Nix store — never backed up
├── var           # All service state — backed up
├── home          # User data
├── reserved      # 10G reservation to prevent pool full
└── containers    # ext4 zvol for Podman (acltype compat)
```

**boulder (machine 2):** Same structure.

**vps:** Simple ext4 (no ZFS needed for 20GB control plane).

### NFS mount pattern

All machines use consistent NFS mount configuration:

```nix
# modules/nfs/default.nix (shared pattern)
fileSystems."/mnt/nas/${name}" = {
  device = "${vars.nasIP}:/mnt/pool/${name}";
  fsType = "nfs";
  options = [
    "nfsvers=4.1"      # NFSv4.1 — max supported by Synology DSM
    "hard"             # Retry indefinitely (vs soft which errors)
    "noatime"          # Reduce write overhead
    "x-systemd.automount"      # Mount on first access
    "x-systemd.idle-timeout=600"  # Unmount after 10 min idle
  ];
};
```

Services depending on NAS add systemd ordering:
```nix
systemd.services.<name>.after = [ "mnt-nas-photos.mount" ];
systemd.services.<name>.requires = [ "mnt-nas-photos.mount" ];
```

### Permission model

NAS exports use `all_squash` to map all clients to a single NAS user. NixOS services run as their own users (e.g., `jellyfin`, `immich`). To avoid permission issues:

1. **NAS side**: `all_squash` with `anonuid`/`anongid` matching a shared media user (e.g., UID 1000)
2. **NixOS side**: Add service users to a shared group with GID matching NAS export
3. **Alternative**: Use `no_root_squash` with careful firewall rules (less secure)

### Services requiring NAS storage

| Machine | Service | NAS mount | Purpose |
|---------|---------|-----------|---------|
| pebble | Restic backup | `/mnt/nas/backup/pebble` | Backup target |
| boulder | Immich | `/mnt/nas/photos` | Photo library |
| boulder | Jellyfin | `/mnt/nas/media` | Video/music library |
| boulder | Paperless | `/mnt/nas/documents` | Document archive |
| boulder | Restic backup | `/mnt/nas/backup/boulder` | Backup target |

## Unified port allocation table

All ports across all machines, avoiding conflicts.

### pebble (machine 1) — 192.168.10.50

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 22 | TCP | SSH | Restricted to key auth |
| 53 | TCP/UDP | Pi-hole DNS | Network-wide DNS |
| 80 | TCP | Caddy | HTTP redirect + ACME |
| 443 | TCP | Caddy | HTTPS reverse proxy |
| 1883 | TCP | Mosquitto | MQTT broker |
| 3000 | TCP | Grafana | Monitoring dashboards |
| 3001 | TCP | Uptime Kuma | Status monitoring |
| 3010 | TCP | Homepage | Dashboard (remapped from 3000) |
| 3100 | TCP | Loki | Log aggregation |
| 5580 | TCP | Matter Server | Matter WebSocket |
| 6052 | TCP | ESPHome | Device dashboard |
| 8089 | TCP | Pi-hole Web | Admin UI (remapped from 80) |
| 8123 | TCP | Home Assistant | HA web interface |
| 8222 | TCP | Vaultwarden | Password manager |
| 9090 | TCP | Prometheus | Metrics |
| 10200 | TCP | Wyoming Piper | TTS |
| 10300 | TCP | Wyoming Whisper | STT |
| 10400 | TCP | OpenWakeWord | Wake word |
| 51820 | UDP | NetBird | WireGuard VPN |
| 8443 | TCP | Kanidm | HTTPS/OIDC — proxied by Caddy, not directly exposed |
| 636 | TCP | Kanidm LDAPS | LDAP for Jellyfin |

### boulder (machine 2) — 192.168.10.51

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 22 | TCP | SSH | Restricted to key auth |
| 2283 | TCP | Immich | Photo management |
| 3000 | TCP | Outline | ⚠️ Conflicts with Grafana if moved — remap to 3020 |
| 3456 | TCP | Vikunja | Task management |
| 5432 | TCP | PostgreSQL | Shared database (localhost only) |
| 8010 | TCP | Paperless-ngx | Document management |
| 8080 | TCP | Stirling-PDF | PDF toolkit |
| 8096 | TCP | Jellyfin | Media server |
| 8265 | TCP | Actual Budget | Personal finance |
| 9443 | TCP | Karakeep | Bookmarks (⚠️ default 3000 — remapped) |
| 10300 | TCP | Wyoming Whisper | STT (moved from pebble) |

### vps (NetBird control plane) — netbird.grab-lab.gg

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 22 | TCP | SSH | Restricted to admin IP |
| 80 | TCP | HTTP/ACME | Let's Encrypt challenges |
| 443 | TCP | NetBird | Management + Signal + Dashboard + Relay |
| 3478 | UDP | Coturn STUN | NAT traversal |
| 49152-65535 | UDP | Coturn TURN | Relay media range |

### Port conflict notes

| Service | Default | Remapped | Reason |
|---------|---------|----------|--------|
| Pi-hole Web | 80 | 8089 | Caddy needs 80 |
| Homepage | 3000 | 3010 | Grafana uses 3000 |
| Outline | 3000 | 3020 | Grafana conflict |
| Karakeep | 3000 | 9443 | Multiple 3000 conflicts |

## DNS entries table (subdomain registry)

Single source of truth for all `*.grab-lab.gg` subdomains.

| Subdomain | Target machine | Service | Caddy config |
|-----------|---------------|---------|--------------|
| `pihole.grab-lab.gg` | pebble | Pi-hole Web UI | `reverse_proxy localhost:8089` |
| `grafana.grab-lab.gg` | pebble | Grafana | `reverse_proxy localhost:3000` |
| `prometheus.grab-lab.gg` | pebble | Prometheus | `reverse_proxy localhost:9090` |
| `ha.grab-lab.gg` | pebble | Home Assistant | `reverse_proxy localhost:8123` |
| `uptime.grab-lab.gg` | pebble | Uptime Kuma | `reverse_proxy localhost:3001` |
| `home.grab-lab.gg` | pebble | Homepage | `reverse_proxy localhost:3010` |
| `esphome.grab-lab.gg` | pebble | ESPHome | `reverse_proxy localhost:6052` |
| `vault.grab-lab.gg` | pebble | Vaultwarden | `reverse_proxy localhost:8222` |
| `immich.grab-lab.gg` | boulder | Immich | `reverse_proxy 192.168.10.51:2283` |
| `jellyfin.grab-lab.gg` | boulder | Jellyfin | `reverse_proxy 192.168.10.51:8096` |
| `paperless.grab-lab.gg` | boulder | Paperless-ngx | `reverse_proxy 192.168.10.51:8010` |
| `pdf.grab-lab.gg` | boulder | Stirling-PDF | `reverse_proxy 192.168.10.51:8080` |
| `wiki.grab-lab.gg` | boulder | Outline | `reverse_proxy 192.168.10.51:3020` |
| `tasks.grab-lab.gg` | boulder | Vikunja | `reverse_proxy 192.168.10.51:3456` |
| `bookmarks.grab-lab.gg` | boulder | Karakeep | `reverse_proxy 192.168.10.51:9443` |
| `budget.grab-lab.gg` | boulder | Actual Budget | `reverse_proxy 192.168.10.51:8265` |
| `netbird.grab-lab.gg` | vps | NetBird Dashboard | Direct (not proxied through Caddy) |
| `id.grab-lab.gg` | pebble | Kanidm IdP | `reverse_proxy localhost:8443` (with TLS transport) |

**Pi-hole local DNS**: All subdomains resolve to pebble's IP (`192.168.10.50`) via the wildcard `address=/grab-lab.gg/192.168.10.50`. Caddy on pebble then routes to the correct backend (local or boulder).

**Public DNS (Cloudflare)**: Only `netbird.grab-lab.gg` has a public A record (pointing to VPS). All other subdomains return NXDOMAIN publicly — they only resolve inside the homelab via Pi-hole.

## Identity & Authentication

This homelab uses a **two-tier IdP architecture** — see `docs/IDP-STRATEGY.md` for the full design rationale, per-service auth table, and NixOS configuration snippets.

**Tier 1 — VPS: Pocket ID**
- `ghcr.io/pocket-id/pocket-id:v1.3.1` OCI container at `https://pocket-id.grab-lab.gg`
- Handles NetBird VPN authentication only (PKCE + WebAuthn/passkeys)
- `EmbeddedIdP.Enabled = false` in `management.json`; Pocket ID is the external OIDC provider
- Cannot serve other applications — single OIDC client for the NetBird dashboard

**Tier 2 — pebble: Kanidm**
- Native NixOS module: `services.kanidm` with declarative provisioning
- Provides OIDC + LDAP for all homelab service SSO
- ~50–80 MB RAM idle; embedded SQLite database (no PostgreSQL/Redis)
- Accessible only via VPN — never exposed to the internet
- All OAuth2 clients defined declaratively in their respective service modules

**Why not one IdP:** VPN auth cannot depend on the homelab — chicken-and-egg problem.
Pocket ID on VPS breaks the deadlock. See `docs/IDP-STRATEGY.md` for details.

---

