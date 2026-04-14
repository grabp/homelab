# Self-hosting NetBird VPN behind CGNAT on NixOS

**NetBird's self-hosted control plane runs comfortably on a ~€4/month Hetzner VPS, tunnels reliably through CGNAT via automatic relay fallback, and integrates with NixOS declaratively — but DNS coexistence with Pi-hole and initial NixOS server configuration require careful planning.** Since v0.62.0, NetBird ships an embedded identity provider and combined server binary, collapsing what was once a 7-container stack into just 4 containers with ~500MB idle RAM. The critical tradeoff: peers behind CGNAT's symmetric NAT will almost always relay through the VPS rather than connecting peer-to-peer, adding **~70ms latency** and capping throughput around **7 Mbps** on a budget VPS — acceptable for accessing Home Assistant and media services, but worth understanding upfront.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ARCHITECTURE OVERVIEW                                │
│                                                                             │
│  ┌──────────────┐          ┌──────────────────────────┐                     │
│  │  Mobile/     │          │ VPS (netbird.grab-lab.gg)│                     │
│  │  Laptop      │◄──WG────►│  ┌────────────────────┐  │                     │
│  │  (VPN peer   │  relay   │  │ netbird-server     │  │                     │
│  └──────────────┘  or P2P  │  │ (mgmt+signal+relay)│  │                     │
│         │                  │  └────────────────────┘  │                     │
│         │                  │  ┌─────────┐ ┌────────┐  │                     │
│         │                  │  │dashboard│ │ coturn │  │                     │
│         │                  │  └─────────┘ └────────┘  │                     │
│         │                  │  ┌─────────┐             │                     │
│         │                  │  │ caddy/  │             │                     │
│         │                  │  │ traefik │             │                     │
│         │                  │  └─────────┘             │                     │
│         │                  └──────────┬───────────────┘                     │
│         │                             │ TCP 443, UDP 3478                   │
│         │                             │                                     │
│         │         ┌───────────────────┼──── CGNAT ────┐                     │
│         │         │ ISP NAT (symmetric, no inbound)   │                     │
│         │         └───────────────────┼───────────────┘                     │
│         │                             │                                     │
│         │                  ┌──────────▼───────────────┐                     │
│         │                  │  UniFi Gateway           │                     │
│         │                  │  192.168.10.1            │                     │
│         │                  └──────────┬───────────────┘                     │
│         │                             │                                     │
│         │                  ┌──────────▼───────────────┐                     │
│         └──── WG ─────────►│  HP EliteDesk 705 G4     │                     │
│           (P2P if lucky,   │  NixOS (routing peer)    │                     │
│            relay if CGNAT) │  ├─ NetBird client       │                     │
│                            │  ├─ Pi-hole (DNS :53)    │                     │
│                            │  ├─ Caddy (*.grab-lab.gg)│                     │
│                            │  └─ Services (HA, etc.)  │                     │
│                            │  192.168.10.0/24         │                     │
│                            └──────────────────────────┘                     │
│                                                                             │
│  DNS FLOW: VPN client → NetBird resolver → Pi-hole (match: grab-lab.gg)     │
│            → Caddy IP (192.168.10.x) → routed via NetBird → service         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## How NetBird punches through CGNAT (and when it can't)

NetBird uses a **WebRTC-style ICE negotiation** (via the `pion/ice` library) with a three-tier connection priority system. When Peer A wants to reach Peer B, both exchange ICE candidates through the Signal server (end-to-end encrypted), then simultaneously attempt connectivity checks across all candidate pairs.

**The three tiers, in priority order:**

1. **Direct P2P** (`WorkerICE` direct) — Host and server-reflexive candidates discovered via STUN. Works when at least one peer has Endpoint-Independent Mapping (most home routers). Delivers near line-speed performance using the **WireGuard kernel module** on Linux — a concrete advantage over Tailscale, which uses userspace WireGuard on all platforms.

2. **TURN relay** (`WorkerICE` relayed) — Standard Coturn-based TURN when hole-punching fails. The VPS acts as relay; traffic remains WireGuard-encrypted end-to-end.

3. **NetBird custom relay** (`WorkerRelay`) — Since v0.29.0, a purpose-built relay racing **QUIC** (UDP) and **WebSocket** (TCP 443) simultaneously, using whichever succeeds first. This is the final fallback that works even through deep packet inspection firewalls.

**Behind CGNAT, expect relay.** CGNAT almost universally uses symmetric NAT (Endpoint-Dependent Mapping), where the public port changes per destination. STUN-discovered addresses become useless because the mapping created for the STUN server differs from the mapping needed for the peer. When both endpoints sit behind symmetric NAT, **hole-punching fails virtually 100% of the time**, and NetBird falls back to relay automatically. The `netbird status -d` command shows `ICE candidate: relay` when this happens.

**Keep-alive and recovery behavior** is solid for CGNAT. NetBird hardcodes WireGuard's `PersistentKeepalive` at **25 seconds**, well within the typical CGNAT mapping timeout of 30–120 seconds. A Guard component periodically verifies both transport-layer connectivity and recent WireGuard handshakes. If either fails, it triggers automatic reconnection via the Handshaker. A Network Monitor detects interface and route changes (common with CGNAT IP reassignment) and restarts the engine automatically.

**One known gap**: NetBird does **not proactively upgrade from relay to direct** once a relayed connection is established. If network conditions improve, the connection stays relayed until a failure triggers re-evaluation. Running `netbird down && netbird up` forces fresh ICE negotiation. GitHub issue #3936 documents "stale relay" connections behind CGNAT where the status shows connected but traffic stops flowing — restarting the client resolves this.

**Performance impact of relay**: Real-world reports show relay connections averaging **~7 Mbps** throughput and **~85ms latency** versus **~15ms** for direct P2P. For accessing Home Assistant dashboards, Grafana, and media streaming at moderate quality, this is adequate. For large file transfers, it becomes a bottleneck.

---

## The self-hosted control plane fits on a single €4 VPS

Since **v0.62.0** (December 2025), NetBird dramatically simplified self-hosting. The architecture collapsed from 7+ containers (separate management, signal, relay, Zitadel, CockroachDB, dashboard, reverse proxy) down to **4 containers**:

| Container | Image | Purpose | RAM (idle) |
|-----------|-------|---------|------------|
| `netbird-server` | `netbirdio/netbird:management-latest` | Combined management API + signal server + relay, with embedded Dex IdP | ~200MB |
| `dashboard` | `netbirdio/dashboard:latest` | React web UI for administration | ~40MB |
| `coturn` | `coturn/coturn:latest` | STUN/TURN server (host network mode) | ~30MB |
| Reverse proxy | `traefik:v3.6` or external Caddy | TLS termination, Let's Encrypt | ~40MB |

**Total idle RAM: ~300–400MB.** Under load with 3–10 peers and sporadic traffic, expect **~500–800MB**. The official minimum is 1 vCPU and 2GB RAM. SQLite is the default database — no PostgreSQL container needed for small deployments.

The **embedded Dex identity provider** is the game-changer. It eliminates the Zitadel + CockroachDB combination that previously consumed 1–2GB RAM alone and caused "100% CPU on VPS" reports. First-time setup presents a wizard at `/setup` where you create the initial admin account — no external IdP configuration required.

### VPS provider decision matrix

| Provider | Plan | RAM | vCPU | Storage | Bandwidth | Monthly | Verdict |
|----------|------|-----|------|---------|-----------|---------|---------|
| **Hetzner** | CX22 / CAX11 | 4 GB | 2 | 40 GB NVMe | 20 TB | **€3.79** | ✅ Best value. Community favorite. NetBird docs use Hetzner as example. |
| Oracle Cloud | Always Free A1 | 24 GB | 4 ARM | 200 GB | 10 TB | **$0** | ⚠️ Free but risky — account termination reports, capacity shortages, complex VCN networking. |
| Contabo | Cloud VPS S | 8 GB | 4 | 50 GB NVMe | Unlimited | ~€5.50 | Acceptable. Mixed I/O performance reviews. |
| BuyVM | Slice 2048 | 2 GB | 1 | 40 GB SSD | Unmetered | $7.00 | Works. Dedicated resources, but pricier per GB RAM. |
| Vultr | Cloud Compute | 1 GB | 1 | 25 GB NVMe | 1 TB | $6.00 | ⚠️ 1GB is marginal. $12/mo for 2GB. |
| DigitalOcean | Basic | 2 GB | 2 | 50 GB | 2 TB | $12.00 | Works but 3x Hetzner's price for equivalent specs. |

**Recommendation: Hetzner CX22 at €3.79/month.** It provides double the minimum RAM, 20TB bandwidth, NVMe storage, and locations in Europe and the US. The ARM variant (CAX11) works identically — NetBird's Docker images are multi-arch. A real-world Hetzner deployment reported **0.12 load average and ~12% RAM utilization** after 3 months of production use.

**Oracle Cloud Free Tier** deserves a warning: multiple Oracle Community reports document accounts terminated without warning, especially idle accounts after 30+ days. Converting to Pay-As-You-Go reduces this risk (free resources still apply) but adds billing complexity. Use it for experimentation, not as your sole VPN infrastructure.

### Ports required on the VPS firewall

| Port | Protocol | Service | Required |
|------|----------|---------|----------|
| **80** | TCP | HTTP redirect + ACME challenges | Yes |
| **443** | TCP | Management API, Signal (gRPC/HTTP2), Dashboard, Relay WebSocket | Yes |
| **3478** | UDP | STUN/TURN (Coturn) | Yes |
| **49152–65535** | UDP | TURN relay media range | Yes (for relayed connections) |
| 22 | TCP | SSH (restrict to your IP) | Recommended |

⚠️ **Hetzner firewall caveat**: Hetzner Cloud uses stateless firewalls. You must also open the ephemeral UDP port range from `/proc/sys/net/ipv4/ip_local_port_range` for TURN return traffic to work properly.

### DNS records needed

| Type | Name | Value | Purpose |
|------|------|-------|---------|
| **A** | `netbird.grab-lab.gg` | `<VPS_PUBLIC_IP>` | All control plane services (management, signal, dashboard) |

That's it — one A record. Since v0.29.0, management, signal, and dashboard share port 443 via HTTP/2 protocol negotiation. If you later enable NetBird's built-in reverse proxy feature (v0.65+), add a wildcard CNAME `*.netbird.grab-lab.gg → netbird.grab-lab.gg`. No SRV or TXT records are needed.

**Cloudflare users**: Set the record to **"DNS only"** (gray cloud). Cloudflare's HTTP proxy breaks gRPC, which NetBird requires.

---

## Identity provider: use the embedded Dex and move on

NetBird supports Zitadel, Keycloak, Authentik, PocketID, and several cloud IdPs — but for a 3–10 peer homelab, the **embedded Dex IdP** (built into `netbird-server` since v0.62.0) is the clear choice. It adds zero containers, zero RAM overhead, and zero configuration complexity. Users are managed directly in the Dashboard with email/password authentication, bcrypt-hashed passwords, and AES-256-GCM encryption.

If you later deploy Authentik on the homelab for broader SSO, NetBird supports adding it as an **external OIDC provider** alongside the embedded IdP. The management server needs to reach Authentik's `.well-known/openid-configuration` endpoint, and Authentik needs to be accessible from client devices during the auth flow. Since Authentik would be behind CGNAT on the homelab, you'd either expose it via NetBird's reverse proxy or via a Cloudflare Tunnel — but this is a future optimization, not a day-one requirement.

**Resource comparison of IdP options** for context:

- **Embedded Dex**: 0 extra containers, ~0 extra RAM — ✅ use this
- **PocketID**: 1 container, ~50–100MB — lightweight alternative if you want passkey support
- **Zitadel**: 2 containers (+ CockroachDB), ~1–2GB — ❌ overkill, known to peg CPU on small VPS
- **Keycloak**: 1–2 containers (+ PostgreSQL), ~500MB–1GB — enterprise-grade, unnecessary here
- **Authentik**: 3+ containers (+ PostgreSQL + Redis), ~800MB–1.5GB — great for homelab SSO but not for VPS

---

## NixOS configuration for the homelab client

The NixOS NetBird module was substantially reworked (PR #354032) and now uses `services.netbird.clients.<name>` as the primary interface. Each client creates a dedicated systemd service, CLI command, and WireGuard interface.

### Homelab client configuration

```nix
# hosts/homelab/netbird.nix
{ config, ... }:
{
  # Secret management via sops-nix
  sops.secrets."netbird/setup_key" = {
    sopsFile = ../../secrets/homelab.yaml;
  };

  # systemd-resolved: needed for NetBird DNS, but must coexist with Pi-hole
  services.resolved = {
    enable = true;
    extraConfig = ''
      DNSStubListener=no
    '';
    # Pi-hole handles DNS; resolved is only here for NetBird's resolvectl integration
  };

  # NetBird VPN client
  services.netbird.clients.wt0 = {
    port = 51820;
    openFirewall = true;
    openInternalFirewall = true;
    ui.enable = false;

    login = {
      enable = true;
      setupKeyFile = config.sops.secrets."netbird/setup_key".path;
    };

    # ⚠️ VERIFY: config overlay for management URL may work via config.d/*.json
    # If not, run once manually after first deploy:
    # netbird-wt0 up --management-url https://netbird.grab-lab.gg \
    #   --setup-key $(cat /run/secrets/netbird/setup_key)
  };

  # Enable IP forwarding for route advertisement
  services.netbird.useRoutingFeatures = "both";

  # Firewall: forward traffic from VPN interface to LAN
  networking.firewall = {
    extraCommands = ''
      iptables -A FORWARD -i wt0 -j ACCEPT
      iptables -A FORWARD -o wt0 -j ACCEPT
    '';
  };
}
```

### The systemd-resolved and Pi-hole coexistence solution

This is the **#1 pain point** reported by the community. NetBird requires `systemd-resolved` for its DNS route management (registering match-domain nameservers via `resolvectl`). Pi-hole wants port 53. The solution: **disable the stub listener** with `DNSStubListener=no`.

This keeps `systemd-resolved` running as a routing daemon (so NetBird can register its DNS nameservers for match domains like `grab-lab.gg`) while freeing port 53 for Pi-hole. The `/etc/resolv.conf` symlink should point to Pi-hole's IP rather than the stub address `127.0.0.53`. NixOS handles this automatically when `DNSStubListener=no` is set.

An alternative approach uses NetBird's `NB_DNS_RESOLVER_ADDRESS` environment variable to move its embedded resolver off port 53, but this has had bugs in past versions (GitHub #2529) and should be tested carefully. ⚠️ VERIFY whether this is reliable in v0.68.x.

### Route advertisement is configured server-side

The `useRoutingFeatures = "both"` NixOS option enables IP forwarding (the kernel-level prerequisite), but **route creation itself happens in the NetBird Dashboard**, not in NixOS configuration:

1. Dashboard → Network Routes → Add Route
2. Network: `192.168.10.0/24`
3. Routing Peer: select the homelab machine
4. Distribution Groups: select which peers can use this route
5. Enable masquerading (recommended for simplicity)

---

## VPS deployment and portability strategy

### NixOS on the VPS with nixos-anywhere

The cleanest approach is managing both machines from **one Nix flake** with `nixos-anywhere` for initial VPS provisioning and `deploy-rs` for ongoing updates.

**nixos-anywhere** SSHs into any Linux VPS, kexec-boots into a NixOS installer in RAM, partitions disks via `disko`, and installs your flake configuration. It requires ≥1GB RAM and works on Hetzner, DigitalOcean, Vultr, OVH, and most providers offering SSH access. It's actively maintained by the nix-community (Numtide).

```bash
# Initial VPS provisioning
nix run github:nix-community/nixos-anywhere -- \
  --flake .#vps \
  root@<VPS_IP>

# Subsequent updates via deploy-rs
deploy .#vps
```

### Multi-machine flake structure

```
homelab-infra/
├── flake.nix              # nixosConfigurations for homelab + vps
├── hosts/
│   ├── homelab/
│   │   ├── configuration.nix
│   │   ├── hardware-configuration.nix
│   │   └── netbird.nix    # Client config (above)
│   └── vps/
│       ├── configuration.nix
│       ├── disk-config.nix # disko partitioning
│       └── netbird-server.nix
├── modules/
│   └── common.nix         # Shared: SSH, users, nix settings
├── secrets/
│   ├── homelab.yaml       # sops-encrypted
│   └── vps.yaml
└── .sops.yaml             # age key configuration
```

```nix
# flake.nix (key sections)
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = { url = "github:nix-community/disko"; inputs.nixpkgs.follows = "nixpkgs"; };
    deploy-rs.url = "github:serokell/deploy-rs";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, disko, deploy-rs, sops-nix, ... }: {
    nixosConfigurations = {
      homelab = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/homelab/configuration.nix
        ];
      };
      vps = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux"; # or aarch64-linux for Hetzner CAX
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/vps/configuration.nix
        ];
      };
    };

    deploy.nodes = {
      homelab = {
        hostname = "homelab.local";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos
            self.nixosConfigurations.homelab;
        };
      };
      vps = {
        hostname = "netbird.grab-lab.gg";
        sshUser = "root";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos
            self.nixosConfigurations.vps;
        };
      };
    };
  };
}
```

### Recommended: OCI containers on NixOS VPS

The VPS still runs NixOS (managed via the same flake + deploy-rs), but NetBird server
components run as Podman OCI containers via `virtualisation.oci-containers`. Native NixOS
Caddy handles TLS termination; native coturn handles STUN/TURN.

**Since NetBird v0.62.0**, the 7-container stack collapses to 3 containers:
- `netbirdio/netbird:management-latest` — combined management + signal + relay + embedded Dex IdP
- `netbirdio/dashboard:latest` — React web UI
- `coturn/coturn:latest` — STUN/TURN (host network)

The **embedded Dex IdP** requires zero configuration — it auto-sets up during the
`/setup` wizard on first boot. No Zitadel, no CockroachDB, no external accounts.

See **NIX-PATTERNS.md Pattern 19** for the full OCI container configuration and
**Pattern 20** for the native Caddy reverse proxy setup. These are the patterns
used in `machines/nixos/vps/netbird-containers.nix`.

⚠️ **Pin image tags before production** — `management-latest` is a rolling tag. Use
a specific version like `netbirdio/netbird:v0.68.1` in your NixOS config.

---

### ⚠️ EXPERIMENTAL: NixOS native server module (do not use in production)

The `services.netbird.server` NixOS module exists with ~41 options in nixpkgs, but
**is not production-ready as of nixos-25.11**. Issues encountered during testing:
- Sparse documentation — options are unclear without reading nixpkgs source
- Complex OIDC chicken-and-egg startup ordering
- Unclear interactions between coturn, management, and signal components
- Configuration failures that are difficult to diagnose

**Recommendation: use OCI containers (above) instead.** The config below is preserved
for reference only — it has NOT been tested successfully in this project.

```nix
# hosts/vps/netbird-server.nix
{ config, ... }:
let
  domain = "grab-lab.gg";
  netbirdDomain = "netbird.${domain}";
in
{
  sops.secrets = {
    netbird-turn-password = { sopsFile = ../../secrets/vps.yaml; };
    netbird-encryption-key = { sopsFile = ../../secrets/vps.yaml; };
    netbird-relay-secret = { sopsFile = ../../secrets/vps.yaml; };
  };

  services.netbird.server = {
    enable = true;
    domain = netbirdDomain;

    coturn = {
      enable = true;
      passwordFile = config.sops.secrets.netbird-turn-password.path;
    };

    signal.enable = true;
    dashboard.enable = true;

    management = {
      enable = true;
      domain = netbirdDomain;
      turnDomain = netbirdDomain;
      singleAccountModeDomain = netbirdDomain;
      # ⚠️ VERIFY: oidcConfigEndpoint may not be needed with embedded IdP
      settings = {
        DataStoreEncryptionKey._secret =
          config.sops.secrets.netbird-encryption-key.path;
        TURNConfig.Secret._secret =
          config.sops.secrets.netbird-turn-password.path;
        Relay = {
          Addresses = [ "rels://${netbirdDomain}:443" ];
          Secret._secret = config.sops.secrets.netbird-relay-secret.path;
        };
      };
    };
  };

  # TLS via Let's Encrypt
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@${domain}";
  };

  networking.firewall = {
    allowedTCPPorts = [ 80 443 ];
    allowedUDPPorts = [ 3478 ];
    allowedUDPPortRanges = [{ from = 49152; to = 65535; }];
  };
}
```

### Docker Compose reference (not used in this project)

The official Docker Compose quickstart is kept here for reference. On NixOS, use
`virtualisation.oci-containers` (see the Recommended section above) — it provides
the same container images but with declarative NixOS management instead of
docker-compose.yml files.

If you prefer Docker on a minimal Ubuntu/Debian VPS rather than NixOS:

```bash
# One-command deployment
export NETBIRD_DOMAIN=netbird.grab-lab.gg
curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh | bash
```

This generates `docker-compose.yml`, `config.yaml`, and `turnserver.conf` automatically. It asks which reverse proxy to use (Traefik is default; Caddy is option 4). The generated stack uses the embedded Dex IdP with no external dependencies.

For portability, commit the generated files to your git repo and add a cloud-init user-data script:

```yaml
#cloud-config
packages: [docker.io, docker-compose-plugin]
runcmd:
  - systemctl enable --now docker
  - cd /opt/netbird && docker compose up -d
```

### Migration strategy when switching VPS providers

**State to preserve** (back up these before tearing down):

- `/var/lib/netbird/` (or Docker volume `netbird_management`) — SQLite database with all peer registrations, ACLs, groups, DNS config
- The `DataStoreEncryptionKey` — without this, the database is **unreadable**
- TLS certificates (Let's Encrypt `acme.json` or Caddy's cert storage)
- `config.yaml` and `turnserver.conf`

**Migration steps**: Back up state → provision new VPS → restore state before starting services → update the `netbird.grab-lab.gg` A record to the new IP → clients reconnect automatically. Set DNS TTL to **60–300 seconds** to minimize transition time. Peers do not need re-registration — setup keys and peer enrollment survive migration because they're in the database.

---

## Split DNS: connecting VPN clients through Pi-hole to homelab services

The DNS flow requires three pieces working together: NetBird's built-in DNS nameserver groups, Pi-hole's local DNS, and Caddy's reverse proxy.

**Configuration in the NetBird Dashboard:**

1. **Match-domain nameserver** — Dashboard → DNS → Nameservers → Add Nameserver:
   - Name: `pihole-homelab`
   - Nameserver IP: Pi-hole's NetBird overlay IP (e.g., `100.x.y.z`) or LAN IP (`192.168.10.x` — requires the route to 192.168.10.0/24 to be active)
   - Port: 53, Type: UDP
   - Match Domains: `grab-lab.gg` (automatically matches all subdomains)
   - Distribution Groups: All

2. **Default nameserver** — A second nameserver entry with no match domains:
   - Nameserver IPs: `1.1.1.1` and `8.8.8.8` as fallbacks
   - This handles all non-homelab DNS when Pi-hole is unreachable

**Pi-hole configuration**: Add Local DNS records (or Conditional Forwarding) so `*.grab-lab.gg` resolves to Caddy's LAN IP (e.g., `192.168.10.5`). VPN clients query Pi-hole via the NetBird tunnel, get Caddy's LAN IP, and traffic routes through the NetBird routing peer to reach the service.

**Custom DNS Zones** (v0.63+) offer a simpler alternative: create A records directly in NetBird's Dashboard (e.g., `ha.grab-lab.gg → 192.168.10.5`) without needing Pi-hole in the resolution chain at all. These records are distributed directly to peers. The downside is you lose Pi-hole's ad-blocking for those queries.

**NetBird's eBPF/XDP trick**: On Linux, NetBird uses eBPF to share port 53 between its own resolver and other DNS services. This means Pi-hole and NetBird's resolver can technically coexist on port 53 on the same host — but community reports suggest this can be fragile. The `DNSStubListener=no` approach described above is more reliable.

---

## UniFi network: no special configuration needed

NetBird makes only **outbound connections** from the homelab — TCP 443 to the management/signal server and UDP 3478 to Coturn. No port forwarding is needed on the UniFi gateway, which is exactly the point for CGNAT scenarios.

**UPnP**: Keep it **disabled**. NetBird doesn't use UPnP for NAT traversal (it relies on STUN/TURN), and UPnP is a significant security risk — any LAN device can open arbitrary ports.

**Potential interference points to check:**

- **IDS/IPS (Threat Management)**: WireGuard traffic is encrypted UDP that IDS can't inspect, but unusual UDP patterns to the VPS might trigger false positives. If connections fail, check System Log → Security Detection and add the VPS IP to the IDS/IPS exclusion list.
- **Smart Queues**: Uses fq_codel which can deprioritize bulk UDP. Disable if experiencing latency spikes on the VPN.
- **Built-in WireGuard VPN server**: If UniFi's own WireGuard server is enabled, it defaults to port 51820 — the same as NetBird. Change NetBird's port in the NixOS config (`port = 51821`).

**NAT type detection**: Run `netbird status -d` after connecting. Look for `ICE candidate (Local/Remote)`. Behind CGNAT, you'll see `srflx` (server reflexive, meaning STUN discovered an address) or `relay` (meaning hole-punching failed). If both sides show `host`, you're on the same LAN — the best case.

---

## Security model: what a VPS compromise means

The most important security property: **the VPS never sees your traffic**. WireGuard provides end-to-end encryption between peers. Private keys never leave the devices. Even relayed traffic passes through Coturn encrypted — the relay cannot decrypt it.

**If an attacker compromises the VPS**, they can: see peer metadata and network topology (public keys, hostnames, connection times), add rogue peers by creating setup keys, modify ACL policies to open unauthorized access, and disrupt service by stopping containers. They **cannot** decrypt any peer-to-peer traffic, perform man-in-the-middle attacks (would need private keys from endpoints), or access services directly without adding a peer.

**Recommended ACL policies** (delete the default "All → All" policy):

```
homelab-servers ↔ homelab-servers  (any protocol, bidirectional)
personal-devices → homelab-servers (TCP 80, 443 only)
mobile-devices → homelab-servers   (TCP 80, 443 only)
admin-devices → homelab-servers    (TCP 22, 80, 443)
all-peers → pihole                 (UDP 53)
```

**Setup key strategy**: Create one **reusable** key (usage limit = number of servers) assigned to a "homelab-servers" group with long expiration. Create **one-off** keys for personal devices with 24–72 hour expiration. Setup keys are stored as bcrypt hashes in the database since recent versions. Revoke keys after enrollment.

**Key rotation**: WireGuard performs session key rotation every ~2 minutes automatically (built-in perfect forward secrecy). Static WireGuard keypairs persist for the peer's lifetime — rotation requires removing and re-adding the peer. For post-quantum protection, NetBird supports **Rosenpass** (`--enable-rosenpass`), which automatically rotates WireGuard pre-shared keys using quantum-resistant algorithms. It's experimental and both peers must enable it.

---

## Failure modes and what survives an outage

| Failure | Impact | Recovery |
|---------|--------|----------|
| **VPS goes down** | Existing P2P connections **continue working**. No new connections. No policy updates. Dashboard inaccessible. | Connections persist until WireGuard handshake timeout (~5 min). Restart VPS or migrate. |
| **Homelab reboots** | NetBird systemd service auto-starts, reconnects to management, re-establishes peer tunnels. | Automatic. ~10–30 seconds to fully reconnect. |
| **CGNAT mapping changes** | 25s keepalive usually prevents this. If mapping resets, Guard detects failed handshake and triggers re-ICE. | Automatic within ~30–60 seconds. May temporarily fall to relay. |
| **ISP assigns new public IP** | Network Monitor detects route/interface change, restarts engine. | Automatic. New ICE negotiation with new reflexive candidates. |
| **Peers on same LAN** | Connect directly via host candidates (priority 1). Traffic stays on LAN, bypasses VPS entirely. | Automatic. `netbird status` shows `host/host` candidates. |
| **Stale relay** (known bug) | Status shows "Connected" but traffic stops. WireGuard handshake timestamp stale. | Manual: `netbird down && netbird up` or restart systemd service. |

**Monitoring**: Run `netbird status -d` periodically or script it. Check for peers showing "Connected" with stale handshake timestamps (>5 minutes). For automated monitoring, query the management API (`/api/peers`) and alert when peers haven't been seen recently. Consider a simple systemd timer that runs `netbird-wt0 status --json` and checks handshake freshness.

---

## Step-by-step deployment order

1. **Register domain** — Ensure `grab-lab.gg` is active with DNS you control. Create an A record for `netbird.grab-lab.gg` pointing to `<placeholder>` (will update after VPS provisioning). Set TTL to 300 seconds.

2. **Provision the VPS** — Spin up a Hetzner CX22 (€3.79/mo). Note the public IP. Update the DNS A record for `netbird.grab-lab.gg` to this IP.

3. **Deploy control plane on VPS** — Either:
   - **NixOS path**: Run `nixos-anywhere --flake .#vps root@<VPS_IP>` to install NixOS with your server configuration.
   - **Docker path**: SSH in, install Docker, run the `getting-started.sh` quickstart with `NETBIRD_DOMAIN=netbird.grab-lab.gg`.

4. **Verify VPS** — Open `https://netbird.grab-lab.gg` in a browser. Complete the setup wizard (create admin account). Verify TLS certificate is valid.

5. **Create setup keys** — In Dashboard → Setup Keys, create a reusable key for homelab servers (assign to "homelab-servers" group) and one-off keys for personal devices.

6. **Store setup key in sops** — Encrypt the homelab setup key into `secrets/homelab.yaml` using sops-nix.

7. **Deploy NetBird client on homelab** — Add the NixOS NetBird client configuration (see above). Run `nixos-rebuild switch`. If auto-login doesn't set the management URL, run `netbird-wt0 up --management-url https://netbird.grab-lab.gg --setup-key $(cat /run/secrets/netbird/setup_key)` once.

8. **Configure routes** — In Dashboard → Network Routes, add `192.168.10.0/24` with the homelab as routing peer. Enable masquerading.

9. **Configure DNS** — In Dashboard → DNS → Nameservers, add Pi-hole as match-domain nameserver for `grab-lab.gg`. Add `1.1.1.1`/`8.8.8.8` as default nameservers.

10. **Configure ACLs** — Delete the default "All → All" policy. Create specific policies per group and service.

11. **Test from a mobile device** — Install NetBird app, authenticate, verify you can reach `ha.grab-lab.gg` and that DNS resolution flows through Pi-hole.

12. **Set up monitoring** — Create a systemd timer or cron job that checks `netbird-wt0 status` and alerts on disconnection.

---

## Conclusion

NetBird self-hosted has matured into a viable homelab VPN, especially after v0.62.0 eliminated the heavyweight Zitadel dependency. The total cost is **~€4/month** for a Hetzner CX22 VPS plus your existing domain. Behind CGNAT, accept that connections will be relayed rather than peer-to-peer — the ~7 Mbps throughput and ~85ms latency are adequate for dashboard access and light media streaming, though not ideal for bulk transfers.

The three areas requiring the most attention are **DNS coexistence** (systemd-resolved + Pi-hole, solved with `DNSStubListener=no`), **gRPC proxy configuration** (Caddy h2c syntax for management/signal gRPC endpoints — verify carefully), and **stale relay monitoring** (a known bug in CGNAT scenarios requiring occasional client restarts). The `services.netbird.server` NixOS module is not production-ready — use `virtualisation.oci-containers` on the NixOS VPS with the official NetBird images. The embedded Dex IdP (since v0.62.0) eliminates the need for external IdP accounts entirely.

Key version to target: **NetBird v0.68.1** (released April 8, 2026). The embedded IdP, combined server container, and consolidated port architecture make this the best era yet for self-hosting NetBird on a budget.
