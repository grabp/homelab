# Second Machine Research — HP EliteDesk 705 G4 (boulder)

**The second homelab machine runs media, productivity, and compute-intensive services that benefit from dedicated resources and separate maintenance windows.** With 32 GB RAM and AMD Ryzen APU, it handles Immich photo processing, Jellyfin transcoding, Paperless-ngx OCR, and a Windows VM for edge cases — all services that would compete for resources with Home Assistant's real-time requirements on machine 1.

---

## Hardware

| Component | Specification | Notes |
|-----------|--------------|-------|
| Model | HP EliteDesk 705 G4 SFF | Same chassis family as pebble (ProDesk) |
| CPU | AMD Ryzen 5 PRO 2400G | 4C/8T, 3.6 GHz base, Vega 11 iGPU |
| RAM | 32 GB DDR4 | 2x16 GB, expandable |
| Storage | 512 GB NVMe SSD | System + service state |
| iGPU | AMD Vega 11 | VAAPI transcoding for Jellyfin |
| Network | 1 Gbit Ethernet | Static IP on 192.168.10.0/24 |

**VAAPI advantage**: The Vega 11 iGPU supports hardware-accelerated video transcoding via VAAPI, making Jellyfin transcoding efficient without a discrete GPU. This is significantly better than pure CPU transcoding on machine 1's Intel iGPU-less Xeon.

---

## Services planned for boulder

| Service | Purpose | RAM estimate | Storage location | Notes |
|---------|---------|--------------|------------------|-------|
| **Immich** | Photo management | 2–4 GB | NAS (photos), local (DB) | ML inference for face/object recognition |
| **Jellyfin** | Media server | 1–2 GB | NAS (media), local (transcodes) | VAAPI transcoding enabled |
| **Paperless-ngx** | Document management | 500 MB–1 GB | NAS (documents), local (DB) | OCR processing |
| **Stirling-PDF** | PDF toolkit | 200–500 MB | Local only | Stateless, no persistence needed |
| **Outline** | Wiki/docs | 500 MB | Local | PostgreSQL backend |
| **Vikunja** | Task management | 200–300 MB | Local | PostgreSQL backend |
| **Karakeep** | Bookmark manager | 100–200 MB | Local | SQLite backend |
| **Actual Budget** | Personal finance | 100–200 MB | Local | SQLite, local-first sync |
| **Windows VM** | Edge cases | 4–8 GB (when running) | Local | QEMU/libvirt, occasional use |
| **Whisper** | Speech-to-text | 500–800 MB | Local | Moved from machine 1 for resource isolation |

**Total estimated RAM**: ~10–18 GB steady state (without Windows VM), leaving headroom for bursts and the VM when needed.

---

## Architecture decisions

### PostgreSQL: shared instance vs per-service

**Recommendation: Single shared PostgreSQL instance** for Outline, Vikunja, Paperless-ngx, and any future services needing PostgreSQL.

Rationale:
- Simplifies backup (one database dump covers all)
- Reduces RAM overhead (one server process, connection pooling)
- NixOS `services.postgresql` module handles user/database creation declaratively
- Each service gets its own database with separate credentials

Services using SQLite (Karakeep, Actual Budget, Immich's sidecar databases) keep their embedded databases — no benefit to migrating them to PostgreSQL.

### Storage: local SSD vs NAS

| Data type | Location | Rationale |
|-----------|----------|-----------|
| Service databases (PostgreSQL, SQLite) | Local SSD | Latency-sensitive, small size |
| Immich photos (originals + generated) | NAS | Large, already backed up on NAS |
| Jellyfin media library | NAS | Large, read-heavy, shared with other devices |
| Paperless documents | NAS | Already backed up, searchable from anywhere |
| Transcoding temp files | Local SSD | I/O intensive, temporary |
| Docker/Podman layers | Local SSD | Latency-sensitive, ephemeral |

### NFS mount pattern

All NAS mounts follow the same pattern as machine 1:

```nix
fileSystems."/mnt/nas/photos" = {
  device = "${vars.nasIP}:/mnt/pool/photos";
  fsType = "nfs";
  options = [
    "nfsvers=4.1"
    "hard"
    "noatime"
    "x-systemd.automount"
    "x-systemd.idle-timeout=600"
  ];
};
```

Services that depend on NAS mounts need `after = [ "mnt-nas-*.mount" ]` in their systemd unit.

### VAAPI transcoding for Jellyfin

Enable hardware transcoding via AMD's VAAPI:

```nix
# Required for VAAPI
hardware.graphics.enable = true;
hardware.graphics.extraPackages = with pkgs; [
  vaapiVdpau
  libvaMesa
];

# Jellyfin container needs access to render device
virtualisation.oci-containers.containers.jellyfin = {
  image = "jellyfin/jellyfin:10.10.x";
  extraOptions = [
    "--device=/dev/dri:/dev/dri"  # GPU access
    "--network=host"               # DLNA discovery
  ];
  # ...
};
```

### Windows VM via libvirt

For occasional Windows-only tasks (specific software, testing):

```nix
virtualisation.libvirtd.enable = true;
programs.virt-manager.enable = true;
users.users.admin.extraGroups = [ "libvirtd" ];
```

VM storage on local SSD for performance. GPU passthrough is theoretically possible but complex with a single GPU — prefer using the VM headless via RDP or without GPU acceleration.

---

## Service configurations

### Immich

**Module status**: ❌ No native NixOS module. Use Podman containers.

Immich requires multiple containers (server, machine learning, Redis, PostgreSQL). The official `docker-compose.yml` is the reference.

```nix
# Simplified — actual implementation will use virtualisation.oci-containers
# with proper volume mounts, networking, and environment variables
```

Key considerations:
- Use Immich's built-in PostgreSQL or connect to shared instance (⚠️ VERIFY compatibility)
- ML container needs significant RAM for face recognition
- Photo library on NAS; database on local SSD
- Hardware-accelerated ML via AMD GPU is experimental

### Jellyfin

**Module status**: ✅ `services.jellyfin` EXISTS.

```nix
services.jellyfin = {
  enable = true;
  openFirewall = true;
};

# Grant GPU access
systemd.services.jellyfin.serviceConfig.SupplementaryGroups = [ "render" "video" ];

# Media library (read-only NAS mount)
fileSystems."/mnt/nas/media" = { ... };
services.jellyfin.dataDir = "/var/lib/jellyfin";  # Metadata on local SSD
```

### Paperless-ngx

**Module status**: ✅ `services.paperless` EXISTS.

```nix
services.paperless = {
  enable = true;
  address = "127.0.0.1";
  port = 8010;
  consumptionDir = "/mnt/nas/paperless/consume";
  mediaDir = "/mnt/nas/paperless/media";
  dataDir = "/var/lib/paperless";
  settings = {
    PAPERLESS_OCR_LANGUAGE = "eng+pol";
    PAPERLESS_TIME_ZONE = vars.timeZone;
  };
};
```

### Stirling-PDF

**Module status**: ❌ No native module. Use Podman.

```nix
virtualisation.oci-containers.containers.stirling-pdf = {
  image = "frooodle/s-pdf:latest";
  ports = [ "8080:8080" ];
  environment = {
    DOCKER_ENABLE_SECURITY = "false";
  };
};
```

### Outline

**Module status**: ❌ No native module. Use Podman or manual systemd service.

Requires PostgreSQL and Redis. Can share PostgreSQL with other services.

### Vikunja

**Module status**: ❌ No native module. Use Podman.

Supports PostgreSQL backend. API + frontend can be same container with embedded frontend.

### Karakeep

**Module status**: ❌ No native module. Use Podman.

SQLite backend, simple single-container deployment.

### Actual Budget

**Module status**: ❌ No native module. Use Podman.

Local-first design — server is optional but enables sync between devices.

---

## Resource isolation from machine 1

Moving Whisper from pebble to boulder:
- Frees ~500–800 MB RAM on pebble
- Whisper on boulder connects to HA on pebble over LAN (latency negligible)
- HA configuration: Wyoming integration pointing to `boulder.lan:10300`
- If boulder is down, voice assistant degrades gracefully (no STT)

---

## Deployment order (Phase 2 stages)

After machine 1 is stable and all Phase 1 stages complete:

1. **Stage 11: Base system** — Add to flake, disko (ZFS), SSH, monitoring (node_exporter + promtail), NetBird client
2. **Stage 12: PostgreSQL** — Shared instance for multiple services
3. **Stage 13: Paperless-ngx + Stirling-PDF** — Document management
4. **Stage 14: Immich** — Photo management with NAS integration
5. **Stage 15: Jellyfin** — Media server with VAAPI transcoding
6. **Stage 16: Productivity apps** — Outline, Vikunja, Karakeep, Actual Budget
7. **Stage 17: Windows VM** — libvirt/QEMU setup
8. **Stage 18: Whisper migration** — Move STT from pebble to boulder

---

## Network integration

- **Static IP**: `192.168.10.51` (or next available in homelab range)
- **DNS**: Pi-hole on pebble resolves `boulder.grab-lab.gg` and service subdomains
- **Reverse proxy**: Caddy on pebble proxies to boulder services over LAN
- **NetBird**: boulder joins as another peer; accessible remotely via VPN
- **Monitoring**: Prometheus on pebble scrapes boulder's node_exporter; promtail ships logs to Loki

---

## Backup strategy

Same three-tier approach as machine 1:

1. **Sanoid** — ZFS snapshots for /var (service state)
2. **Syncoid** — Replicate to NAS (⚠️ VERIFY NAS has ZFS receive capability)
3. **Restic** — File-level backup to NAS; PostgreSQL dump before snapshot

Special handling:
- **Immich**: PostgreSQL dump + photos already on NAS = no additional backup needed for photos
- **Paperless**: PostgreSQL dump + documents already on NAS
- **Jellyfin**: Metadata only (media is on NAS, not backed up by homelab)

---

## Future considerations

- **Proxmox migration**: If workload grows, consider running NixOS as a VM under Proxmox for easier snapshotting and resource allocation
- **GPU upgrade**: If transcoding demands increase, a dedicated GPU (AMD for VAAPI, or Intel Arc for Quick Sync) could be added
- **High availability**: Critical services (Vaultwarden) stay on pebble; boulder services are acceptable to have downtime during maintenance

---
