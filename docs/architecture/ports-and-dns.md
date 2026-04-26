---
kind: architecture
title: Ports and DNS Reference
tags: [ports, dns, reference]
---

# Ports and DNS Reference

## Port Assignments

### pebble (homelab server) — 192.168.10.50

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 22 | TCP | SSH | Key auth only |
| 53 | TCP/UDP | Pi-hole DNS | Network-wide DNS |
| 80 | TCP | Caddy | HTTP redirect + ACME |
| 443 | TCP | Caddy | HTTPS reverse proxy |
| 636 | TCP | Kanidm LDAPS | For future Jellyfin LDAP integration |
| 1883 | TCP | Mosquitto | MQTT broker (LAN + localhost) |
| 3000 | TCP | Grafana | Monitoring dashboards |
| 3001 | TCP | Uptime Kuma | Status monitoring |
| 3010 | TCP | Homepage | Dashboard (remapped from 3000) |
| 3100 | TCP | Loki | Log aggregation |
| 4180 | TCP | oauth2-proxy | Auth proxy for Homepage |
| 51820 | UDP | NetBird | WireGuard VPN |
| 5580 | TCP | Matter Server | Matter WebSocket API |
| 6052 | TCP | ESPHome | Device dashboard |
| 8222 | TCP | Vaultwarden | Password manager |
| 8443 | TCP | Kanidm HTTPS | Proxied by Caddy only |
| 8089 | TCP | Pi-hole Web | Admin UI (remapped from 80) |
| 9090 | TCP | Prometheus | Metrics |
| 9093 | TCP | Alertmanager | Alerts to Telegram (localhost only) |
| 9115 | TCP | Blackbox exporter | HTTPS probes (localhost only) |
| 10200 | TCP | Wyoming Piper | TTS (localhost only) |
| 10300 | TCP | Wyoming Whisper | STT (localhost only) |
| 10400 | TCP | OpenWakeWord | Wake word (localhost only) |
| 8123 | TCP | Home Assistant | HA web interface (host network) |

### vps (NetBird control plane) — 204.168.181.110

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 22 | TCP | SSH | Restricted to admin IP |
| 80 | TCP | HTTP/ACME | Let's Encrypt challenges |
| 443 | TCP | NetBird | Management + Signal + Dashboard + Relay |
| 443 | TCP | Pocket ID | OIDC provider (Caddy virtual host) |
| 3478 | UDP | Coturn STUN | NAT traversal |
| 49152-65535 | UDP | Coturn TURN | Relay media range |

### Future: boulder (media server) — 192.168.10.51

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 22 | TCP | SSH | Key auth only |
| 2283 | TCP | Immich | Photo management |
| 3020 | TCP | Outline | Wiki (remapped from 3000) |
| 3456 | TCP | Vikunja | Task management |
| 5432 | TCP | PostgreSQL | Shared database (localhost only) |
| 8010 | TCP | Paperless-ngx | Document management |
| 8080 | TCP | Stirling-PDF | PDF toolkit |
| 8096 | TCP | Jellyfin | Media server |
| 8265 | TCP | Actual Budget | Personal finance |
| 9443 | TCP | Karakeep | Bookmarks (remapped from 3000) |

## DNS Entries

### Pi-hole Local DNS (Wildcard Split DNS)

Pi-hole uses dnsmasq with a wildcard entry that resolves `*.grab-lab.gg` to pebble:

```
address=/grab-lab.gg/192.168.10.50
```

Specific VPS-hosted entries override the wildcard:

```
address=/netbird.grab-lab.gg/204.168.181.110
address=/pocket-id.grab-lab.gg/204.168.181.110
```

### Subdomain Registry

| Subdomain | Target | Service | Caddy Config |
|-----------|--------|---------|--------------|
| `pihole.grab-lab.gg` | pebble:8089 | Pi-hole Web UI | `reverse_proxy localhost:8089` |
| `vault.grab-lab.gg` | pebble:8222 | Vaultwarden | `reverse_proxy localhost:8222` |
| `grafana.grab-lab.gg` | pebble:3000 | Grafana | `reverse_proxy localhost:3000` |
| `prometheus.grab-lab.gg` | pebble:9090 | Prometheus | `reverse_proxy localhost:9090` |
| `id.grab-lab.gg` | pebble:8443 | Kanidm | `reverse_proxy localhost:8443` (TLS transport) |
| `home.grab-lab.gg` | pebble:4180 | Homepage | `reverse_proxy localhost:4180` (via oauth2-proxy) |
| `ha.grab-lab.gg` | pebble:8123 | Home Assistant | `reverse_proxy 127.0.0.1:8123` |
| `uptime.grab-lab.gg` | pebble:3001 | Uptime Kuma | `reverse_proxy localhost:3001` |
| `esphome.grab-lab.gg` | pebble:6052 | ESPHome | `reverse_proxy localhost:6052` |
| `netbird.grab-lab.gg` | vps:443 | NetBird Dashboard | Direct (not proxied through pebble) |
| `pocket-id.grab-lab.gg` | vps:443 | Pocket ID | Caddy on VPS |

### Public DNS (Cloudflare)

Only `netbird.grab-lab.gg` has a public A record. All other subdomains return NXDOMAIN publicly — they only resolve inside the homelab via Pi-hole.

| Record | Type | Value | Cloudflare Proxy |
|--------|------|-------|------------------|
| `netbird.grab-lab.gg` | A | 204.168.181.110 | **Disabled** (gray cloud) |

⚠️ **Important:** Cloudflare's HTTP proxy breaks gRPC (used by NetBird Signal). Must use DNS-only mode.

## Port Conflict Resolution

| Service | Default | Remapped | Reason |
|---------|---------|----------|--------|
| Pi-hole Web | 80 | 8089 | Caddy needs port 80 |
| Homepage | 3000 | 3010 | Grafana uses 3000 |
| Outline | 3000 | 3020 | Grafana conflict |
| Karakeep | 3000 | 9443 | Multiple 3000 conflicts |

## Key Files

| File | Purpose |
|------|---------|
| `homelab/caddy/default.nix` | Virtual host routing rules |
| `homelab/pihole/default.nix` | DNS wildcard configuration |
| `machines/nixos/vars.nix` | Domain and IP variables |
| `docs/architecture/overview.md` | Network topology details |
