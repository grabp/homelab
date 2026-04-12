# SERVICE-CONFIGS.md — Per-Service Research

## Pi-hole — OCI container required, no native module

**Module status:** ❌ `services.pihole` does NOT exist in nixpkgs. Must use OCI container.

**OCI image:** `pihole/pihole:2025.02.1` (use specific tag, not `latest`)

**Ports:** 53/tcp, 53/udp (DNS), 8089/tcp (web UI, remapped from 80)

**Volumes:** `/var/lib/pihole/etc-pihole:/etc/pihole`, `/var/lib/pihole/etc-dnsmasq.d:/etc/dnsmasq.d`

**Secrets:** `FTLCONF_webserver_api_password` (web UI password) via `environmentFiles`

**Isolation:** Podman OCI container with `--cap-add=NET_ADMIN`

**Split DNS wildcard:** Create `/var/lib/pihole/etc-dnsmasq.d/04-grab-lab.conf` containing `address=/grab-lab.gg/192.168.10.X`. This resolves ALL `*.grab-lab.gg` subdomains to Caddy's IP.

**Known gotchas:**
- Must disable `systemd-resolved` (`services.resolved.enable = false`) to free port 53
- Pi-hole v6 changed web server from lighttpd to built-in; port config is now in `pihole.toml`
- Container needs `--dns=127.0.0.1` to avoid DNS loops during startup
- Pi-hole does NOT support true wildcard DNS via its GUI — use the dnsmasq config file

```nix
my.services.pihole = {
  enable = true;
  image = "pihole/pihole:2025.02.1";
  webPort = 8089;
};
```

## Caddy — native module with custom plugin build

**Module status:** ✅ `services.caddy` EXISTS. Options: `enable`, `package`, `virtualHosts`, `globalConfig`, `extraConfig`, `adapter`.

**Package:** `pkgs.caddy` (but standard package lacks DNS plugins)

**Custom build:** `pkgs.caddy.withPlugins` (available since NixOS 25.05) — compiles in `caddy-dns/cloudflare` for DNS-01 ACME.

**Ports:** 80/tcp, 443/tcp

**Volumes/state:** `/var/lib/caddy` (certificates — must persist)

**Secrets:** `CLOUDFLARE_API_TOKEN` (Zone:Zone:Read + Zone:DNS:Edit scoped to grab-lab.gg) via `EnvironmentFile`

**Isolation:** Native NixOS module (needs host network for port 80/443)

**Known gotchas:**
- Standard `pkgs.caddy` does NOT include any plugins — always use `withPlugins` for DNS-01
- Plugin version must use pseudo-version format: `@v0.0.0-{date}-{shortrev}`
- Set `hash = ""` on first build; nix gives the correct hash in the error
- Add `resolvers 1.1.1.1` in TLS block to bypass Pi-hole for ACME challenge verification
- Caddy's NixOS module runs as user `caddy` — set sops secret `owner = "caddy"`

```nix
services.caddy = {
  enable = true;
  package = pkgs.caddy.withPlugins {
    plugins = [ "github.com/caddy-dns/cloudflare@v0.0.0-20240703190432-89f16b99c18e" ];
    hash = "sha256-XXXXXXXXXXXX=";  # compute on first build
  };
  virtualHosts."grafana.grab-lab.gg" = {
    extraConfig = "reverse_proxy localhost:3000";
  };
};
```

## NetBird — self-hosted control plane (VPS) + client (homelab)

This project self-hosts the NetBird control plane on a Hetzner CX22 VPS. The homelab (pebble) runs the NetBird client and acts as a routing peer advertising `192.168.10.0/24`. Full research: `docs/NETBIRD-SELFHOSTED.md`.

---

### NetBird server — VPS (`machines/nixos/vps/netbird-server.nix`)

**Module status:** ✅ `services.netbird.server` EXISTS (~41 options). ⚠️ **Documentation is sparse** — treat all options as requiring verification. Docker Compose is the lower-risk initial deployment path.

**Package:** `pkgs.netbird` (server components)

**VPS ports:** 80/tcp (ACME), 443/tcp (management + signal + relay WebSocket), 3478/udp (STUN/TURN), 49152–65535/udp (TURN relay range)

**Secrets:** `netbird-turn-password`, `netbird-encryption-key`, `netbird-relay-secret` in `secrets/vps.yaml`

**DNS record:** A record `netbird.grab-lab.gg → <VPS_PUBLIC_IP>` — set to **DNS only** in Cloudflare (gray cloud). Cloudflare proxying breaks gRPC.

**Identity provider:** Embedded Dex IdP (built into `netbird-server` since v0.62.0) — no external IdP needed. Setup wizard at `/setup` on first deploy.

**RAM:** ~300–500 MB idle (4 containers: netbird-server, dashboard, coturn, reverse proxy)

**Deployment option A — Docker Compose (recommended to start):**

```bash
export NETBIRD_DOMAIN=netbird.grab-lab.gg
curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh | bash
```

Generates `docker-compose.yml`, `config.yaml`, `turnserver.conf` automatically with embedded Dex IdP. Commit generated files to git. Migrate to NixOS module in Stage 9 hardening.

**Deployment option B — NixOS module (⚠️ verify options):**

```nix
# machines/nixos/vps/netbird-server.nix
{ config, vars, ... }:
let netbirdDomain = "netbird.${vars.domain}"; in
{
  sops.secrets = {
    netbird-turn-password  = { sopsFile = ../../../secrets/vps.yaml; };
    netbird-encryption-key = { sopsFile = ../../../secrets/vps.yaml; };
    netbird-relay-secret   = { sopsFile = ../../../secrets/vps.yaml; };
  };

  services.netbird.server = {
    enable  = true;
    domain  = netbirdDomain;
    coturn  = { enable = true; passwordFile = config.sops.secrets.netbird-turn-password.path; };
    signal.enable    = true;
    dashboard.enable = true;
    management = {
      enable                    = true;
      domain                    = netbirdDomain;
      turnDomain                = netbirdDomain;
      singleAccountModeDomain   = netbirdDomain;
      # ⚠️ VERIFY: oidcConfigEndpoint needed? Or handled by embedded Dex automatically?
      settings = {
        DataStoreEncryptionKey._secret =
          config.sops.secrets.netbird-encryption-key.path;
        TURNConfig.Secret._secret =
          config.sops.secrets.netbird-turn-password.path;
        Relay = {
          Addresses  = [ "rels://${netbirdDomain}:443" ];
          Secret._secret = config.sops.secrets.netbird-relay-secret.path;
        };
      };
    };
  };

  security.acme = { acceptTerms = true; defaults.email = vars.adminEmail; };
  networking.firewall = {
    allowedTCPPorts = [ 80 443 ];
    allowedUDPPorts = [ 3478 ];
    allowedUDPPortRanges = [{ from = 49152; to = 65535; }];
  };
}
```

---

### NetBird client — homelab pebble (`homelab/netbird/default.nix`)

**Module status:** ✅ `services.netbird.clients.<name>` EXISTS. Module reworked in nixpkgs PR #354032.

**Package:** `pkgs.netbird`

**Ports:** 51820/udp outbound to VPS (WireGuard); no inbound ports needed (CGNAT)

**Secrets:** `netbird-setup-key` in `secrets/secrets.yaml`

**Known gotchas:**
- **`DNSStubListener=no` is required** for Pi-hole + NetBird coexistence. See Pattern 15 in `docs/NIX-PATTERNS.md`. Pi-hole holds port 53; resolved runs as routing daemon only for NetBird's `resolvectl` calls.
- ⚠️ **Management URL:** `login.managementUrl` option may exist — ⚠️ VERIFY. If not, run once manually after first deploy: `netbird-wt0 up --management-url https://netbird.grab-lab.gg --setup-key $(cat /run/secrets/netbird-setup-key)`
- **Route advertisement** (192.168.10.0/24) is configured in the NetBird Dashboard, not in NixOS. `useRoutingFeatures = "both"` enables the kernel IP forwarding prerequisite only.
- **CGNAT:** expect relay connections (~7 Mbps / ~85ms). `netbird status -d` showing `ICE candidate: relay` is normal, not a failure.
- **Stale relay bug (GitHub #3936):** connection shows "Connected" but traffic stops. Fix: `netbird-wt0 down && netbird-wt0 up`.

```nix
{ config, lib, vars, ... }:
{
  sops.secrets.netbird-setup-key = {};

  services.resolved = {
    enable      = true;
    extraConfig = "DNSStubListener=no";  # Free port 53 for Pi-hole (Pattern 15)
  };

  services.netbird.clients.wt0 = {
    port                 = 51820;
    openFirewall         = true;
    openInternalFirewall = true;   # ⚠️ VERIFY option exists
    ui.enable            = false;
    login = {
      enable       = true;
      setupKeyFile = config.sops.secrets.netbird-setup-key.path;
      # managementUrl = "https://netbird.${vars.domain}";  # ⚠️ VERIFY
    };
  };

  services.netbird.useRoutingFeatures = "both";

  # Forward traffic between VPN interface and LAN
  networking.firewall.extraCommands = ''
    iptables -A FORWARD -i wt0 -j ACCEPT
    iptables -A FORWARD -o wt0 -j ACCEPT
  '';
}
```

**DNS configuration (NetBird Dashboard — done once after Stage 6b deploy):**
1. Dashboard → DNS → Nameservers → Add: IP = Pi-hole overlay IP, Match domain = `grab-lab.gg`
2. Add fallback: `1.1.1.1` / `8.8.8.8`, no match domain
3. Dashboard → Network Routes → Add: `192.168.10.0/24`, routing peer = pebble, masquerade enabled

## Homepage Dashboard — native module with structured config

**Module status:** ✅ `services.homepage-dashboard` EXISTS. Options: `enable`, `services`, `bookmarks`, `widgets`, `settings`, `listenPort`, `environmentFile`, `allowedHosts`.

**Package:** `pkgs.homepage-dashboard`

**Ports:** 3010/tcp (remapped from default 3000 to avoid Grafana conflict)

**Secrets:** API keys for service widgets via `environmentFile`

**Isolation:** Native NixOS module

**Known gotchas:**
- Config stored in `/var/lib/homepage-dashboard`
- `listenPort` option sets the port directly
- Use `environmentFile` for API tokens referenced in widget config as `{{HOMEPAGE_VAR_NAME}}`
- `allowedHosts` may need configuration for reverse proxy access

```nix
services.homepage-dashboard = {
  enable = true;
  listenPort = 3010;
  settings.title = "Homelab";
  services = [
    {
      "Infrastructure" = [
        { "Pi-hole" = { href = "https://pihole.grab-lab.gg"; description = "DNS"; }; }
        { "Caddy" = { href = "https://grab-lab.gg"; description = "Reverse Proxy"; }; }
      ];
    }
  ];
};
```

## Prometheus — native module with extensive exporter ecosystem

**Module status:** ✅ `services.prometheus` EXISTS. Options: `enable`, `globalConfig`, `scrapeConfigs`, `listenAddress`, `port`, `exporters.*`.

**Package:** `pkgs.prometheus`

**Ports:** 9090/tcp

**Secrets:** None required for basic setup

**Isolation:** Native NixOS module

**Known gotchas:**
- Bind to localhost: `services.prometheus.listenAddress = "127.0.0.1"`
- Node exporter auto-integration: `services.prometheus.exporters.node.enable = true`
- Scrape configs use Nix attrsets, not YAML — verify syntax carefully
- Data stored in `/var/lib/prometheus2/` — can grow large, consider retention settings

```nix
services.prometheus = {
  enable = true;
  port = 9090;
  listenAddress = "127.0.0.1";
  globalConfig.scrape_interval = "15s";
  exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
  };
  scrapeConfigs = [
    {
      job_name = "node";
      static_configs = [{ targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ]; }];
    }
  ];
};
```

## Grafana — native module with declarative provisioning

**Module status:** ✅ `services.grafana` EXISTS. Options: `enable`, `settings.*`, `provision.datasources`, `provision.dashboards`, `declarativePlugins`.

**Package:** `pkgs.grafana`

**Ports:** 3000/tcp

**Secrets:** `grafana_admin_password` via `settings.security.admin_password` (use `$__file{/run/secrets/...}` syntax)

**Isolation:** Native NixOS module

**Known gotchas:**
- Use `settings.server.http_addr = "127.0.0.1"` to bind to localhost only
- **Declarative provisioning** of datasources is powerful but requires specific YAML structure in Nix
- `settings.server.root_url` must match your Caddy domain for OAuth/embedding to work
- Plugin installation via `declarativePlugins` with `pkgs.grafanaPlugins.*`

```nix
services.grafana = {
  enable = true;
  settings = {
    server = {
      http_addr = "127.0.0.1";
      http_port = 3000;
      domain = "grafana.grab-lab.gg";
      root_url = "https://grafana.grab-lab.gg";
    };
    security.admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
  };
  provision = {
    enable = true;
    datasources.settings.datasources = [
      { name = "Prometheus"; type = "prometheus"; url = "http://localhost:9090"; isDefault = true; }
      { name = "Loki"; type = "loki"; url = "http://localhost:3100"; }
    ];
  };
};
```

## Loki — native module, note package name

**Module status:** ✅ `services.loki` EXISTS. Options: `enable`, `configuration` (attrset), `configFile` (YAML path), `dataDir`.

**Package:** ✅ `pkgs.grafana-loki` (**not** `pkgs.loki`)

**Ports:** 3100/tcp

**Secrets:** None for basic setup

**Isolation:** Native NixOS module

**Known gotchas:**
- ⚠ Package name is `grafana-loki`, not `loki`
- Can use either `configuration` (Nix attrset) or `configFile` (path to YAML)
- boltdb-shipper is deprecated; use tsdb for new installations
- `auth_enabled: false` for single-tenant homelab

```nix
services.loki = {
  enable = true;
  configuration = {
    auth_enabled = false;
    server.http_listen_port = 3100;

    common = {
      ring = {
        instance_addr = "127.0.0.1";
        kvstore.store = "inmemory";
      };
      replication_factor = 1;
      path_prefix = "/var/lib/loki";
    };

    schema_config.configs = [{
      from = "2024-01-01";
      store = "tsdb";
      object_store = "filesystem";
      schema = "v13";
      index = { prefix = "index_"; period = "24h"; };
    }];

    storage_config.filesystem.directory = "/var/lib/loki/chunks";
  };
};
```

To send systemd journal logs to Loki, use **promtail**:
```nix
services.promtail = {
  enable = true;
  configuration = {
    server = { http_listen_port = 3031; grpc_listen_port = 0; };
    positions.filename = "/tmp/positions.yaml";
    clients = [{ url = "http://localhost:3100/loki/api/v1/push"; }];
    scrape_configs = [{
      job_name = "journal";
      journal = {
        max_age = "12h";
        labels.job = "systemd-journal";
      };
      relabel_configs = [{
        source_labels = [ "__journal__systemd_unit" ];
        target_label = "unit";
      }];
    }];
  };
};
```

⚠ **VERIFY:** `services.promtail` exists in NixOS 25.11. If not, use the `grafana-loki` package's promtail binary as a systemd service.

## Home Assistant — native module exists but OCI recommended

**Module status:** ✅ `services.home-assistant` EXISTS. Options: `enable`, `config`, `configDir`, `package`, `extraComponents`, `extraPackages`, `customComponents`.

**Package:** `pkgs.home-assistant`

**Ports:** 8123/tcp

**Secrets:** HA manages its own secrets via `secrets.yaml`

**Isolation:** Podman OCI container recommended (upstream considers NixOS unsupported; HA version freezes at branch-off)

**Known gotchas:**
- Running natively: HA version freezes at NixOS release branch-off and misses updates. Consider nixpkgs-unstable overlay for latest version.
- Container approach needs `--network=host` for mDNS device discovery (Zigbee, Chromecast, etc.)
- UniFi integration requires a **local admin user** on UniFi controller (not SSO account)
- Configure `http.use_x_forwarded_for: true` and `trusted_proxies: [127.0.0.1]` for Caddy reverse proxy
- HA onboarding is interactive — not fully declarative

**Companion services (Stage 8b):** Deploy Mosquitto (MQTT), the Wyoming voice pipeline (Whisper STT, Piper TTS, OpenWakeWord), ESPHome, and Matter Server alongside HA. HACS is auto-installed via a systemd oneshot. All companion services connect to HA over `localhost` since HA uses `--network=host`. See dedicated sections below for each service.

```nix
# OCI container approach (recommended)
virtualisation.oci-containers.containers.homeassistant = {
  image = "ghcr.io/home-assistant/home-assistant:2025.1";
  autoStart = true;
  volumes = [
    "/var/lib/hass:/config"
    "/etc/localtime:/etc/localtime:ro"
  ];
  extraOptions = [ "--network=host" "--privileged" ];
};
networking.firewall.allowedTCPPorts = [ 8123 ];
```

```nix
# Native approach (if preferred, with version freeze caveat)
services.home-assistant = {
  enable = true;
  extraComponents = [ "unifi" "met" "radio_browser" ];
  config = {
    homeassistant = {
      name = "Home";
      unit_system = "metric";
      time_zone = "America/New_York";
    };
    http = {
      use_x_forwarded_for = true;
      trusted_proxies = [ "127.0.0.1" "::1" ];
    };
    default_config = {};
  };
};
```

## Uptime Kuma — native module, simple configuration

**Module status:** ✅ `services.uptime-kuma` EXISTS. Options: `enable`, `package`, `settings`, `appriseSupport`.

**Package:** `pkgs.uptime-kuma`

**Ports:** 3001/tcp (default)

**Secrets:** None for basic setup (web UI handles auth internally)

**Isolation:** Native NixOS module

**Known gotchas:**
- Settings are passed as environment variables (e.g., `UPTIME_KUMA_PORT`)
- Module description notes "this assumes a reverse proxy to be set"
- State stored in `/var/lib/uptime-kuma/` — SQLite database
- The `appriseSupport` option enables notification integrations

```nix
services.uptime-kuma = {
  enable = true;
  settings = {
    PORT = "3001";
    HOST = "127.0.0.1";
  };
};
```

## Mosquitto — native module, mature and fully declarative

**Module status:** ✅ `services.mosquitto` EXISTS. Options: `enable`, `listeners`, `persistence`, `settings`, `bridges`.

**Package:** `pkgs.mosquitto`

**Ports:** 1883/tcp (MQTT)

**Secrets:** Hashed passwords stored inline (generated with `mosquitto_passwd`, not a secret file)

**Isolation:** Native NixOS module

**Known gotchas:**
- Module sets `per_listener_settings true` globally — users and ACLs must be defined per listener, not globally
- Password hashes go directly in the Nix config (pre-hashed), not via sops; generate with: `nix shell nixpkgs#mosquitto --command mosquitto_passwd -c /tmp/passwd homeassistant`
- Container alternative: `eclipse-mosquitto:2.0.22` — ⚠️ VERIFY tag on Docker Hub

```nix
services.mosquitto = {
  enable = true;
  listeners = [{
    port = 1883;
    users = {
      homeassistant = {
        acl = [ "readwrite #" ];
        hashedPassword = "$7$101$XXXX$XXXX";  # Generate with mosquitto_passwd
      };
      iot = {
        acl = [
          "read homeassistant/command/#"
          "write sensors/#"
        ];
        hashedPassword = "$7$101$YYYY$YYYY";
      };
    };
  }];
};

networking.firewall.allowedTCPPorts = [ 1883 ];
```

## Wyoming Faster-Whisper — native module, apply ProcSubset fix

**Module status:** ✅ `services.wyoming.faster-whisper` EXISTS. Multi-instance pattern: `servers.<name>`.

**Package:** `pkgs.wyoming-faster-whisper`

**Ports:** 10300/tcp (Wyoming protocol, configurable per instance)

**Secrets:** None

**Isolation:** Native NixOS module

**Recommended model:** `small-int8` — best latency/accuracy balance for AMD Ryzen + 16 GB RAM (~500–600 MB RAM, 2–4 s per utterance)

**Known gotchas:**
- ⚠️ **ProcSubset performance bug (nixpkgs PR #372898):** systemd hardening sets `ProcSubset=pid`, blocking faster-whisper from reading `/proc/cpuinfo`. CTranslate2 falls back to a slow code path — a 3-second audio clip takes ~20 s instead of ~3 s. **Always apply the workaround:**
  ```nix
  systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset = lib.mkForce "all";
  ```
- `device = "cuda"` will fail — nixpkgs CTranslate2 is not compiled with CUDA. Use `device = "cpu"`.
- Container alternative: `rhasspy/wyoming-whisper:3.1.0` — ⚠️ VERIFY tag

```nix
services.wyoming.faster-whisper.servers."main" = {
  enable = true;
  uri = "tcp://0.0.0.0:10300";
  model = "small-int8";
  language = "en";
  device = "cpu";
};

# CRITICAL: fix ProcSubset performance bug (see NIX-PATTERNS.md Pattern 10)
systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset = lib.mkForce "all";
```

## Wyoming Piper — native module, no known bugs

**Module status:** ✅ `services.wyoming.piper` EXISTS. Multi-instance pattern: `servers.<name>`.

**Package:** `pkgs.wyoming-piper`

**Ports:** 10200/tcp

**Secrets:** None

**Isolation:** Native NixOS module

**Recommended voice:** `en_US-lessac-medium` (~65 MB, clear female voice). Models auto-download from HuggingFace on first use.

**Known gotchas:**
- Container alternative: `rhasspy/wyoming-piper:2.2.2`

```nix
services.wyoming.piper.servers."main" = {
  enable = true;
  uri = "tcp://0.0.0.0:10200";
  voice = "en_US-lessac-medium";
};
```

## Wyoming OpenWakeWord — native module, single-instance

**Module status:** ✅ `services.wyoming.openwakeword` EXISTS. Single instance (no `servers.<name>` pattern).

**Package:** `pkgs.wyoming-openwakeword`

**Ports:** 10400/tcp

**Secrets:** None

**Isolation:** Native NixOS module

**Built-in wake words:** `okay_nabu`, `hey_jarvis`, `alexa`, `hey_mycroft`, `hey_rhasspy`. Custom `.tflite` models via `customModelsDirectories`.

**Known gotchas:**
- ⚠️ OpenWakeWord v2.0.0 (Oct 2025) **renamed `ok_nabu` to `okay_nabu`** and removed `--preload-model` flag. Use correct model name for your nixpkgs channel's package version.
- Container alternative: `rhasspy/wyoming-openwakeword:2.1.0`

```nix
services.wyoming.openwakeword = {
  enable = true;
  uri = "tcp://0.0.0.0:10400";
  preloadModels = [ "okay_nabu" ];  # ⚠️ VERIFY: "ok_nabu" on older package versions
};
```

## ESPHome — container required, native module has multiple bugs

**Module status:** ✅ `services.esphome` EXISTS but has three unresolved packaging bugs.

**Package:** `pkgs.esphome`

**Ports:** 6052/tcp (dashboard)

**Isolation:** Podman OCI container (recommended)

**Known gotchas:**
- **DynamicUser path bug (nixpkgs #339557):** State directory at `/var/lib/private/esphome` breaks PlatformIO compilation
- **Missing pyserial (nixpkgs #370611):** `esptool` cannot find pyserial; `firmware.factory.bin` not created, blocks ESP32 compilation
- **Missing font component (nixpkgs #272334):** Pillow version mismatches break the `font:` component
- Use `--network=host` for mDNS device discovery; or set `usePing = true` for static-IP devices (bypasses mDNS)
- HA integration: Settings → Devices & Services → ESPHome → enter host IP and port 6052

```nix
virtualisation.oci-containers.containers.esphome = {
  image = "ghcr.io/esphome/esphome:2026.3.1";  # ⚠️ VERIFY tag
  extraOptions = [ "--network=host" ];
  environment.TZ = vars.timeZone;
  volumes = [
    "/var/lib/esphome:/config"
    "/etc/localtime:/etc/localtime:ro"
  ];
  # For USB flashing, add: "--device=/dev/ttyUSB0:/dev/ttyUSB0"
};
```

## Matter Server — container required, CHIP SDK build issues

**Module status:** ✅ `services.matter-server` EXISTS but CHIP SDK build is intractable natively.

**Package:** `pkgs.python-matter-server`

**Ports:** 5580/tcp (WebSocket API)

**Isolation:** Podman OCI container (recommended)

**Known gotchas:**
- **CHIP SDK (home-assistant-chip-core):** Requires architecture-specific binary wheels with non-standard build system (CIPD + GN) — building natively on NixOS is extremely difficult (nixpkgs #255774)
- **Host networking is mandatory** — Matter uses IPv6 link-local multicast. Bridge networking breaks device discovery.
- **D-Bus access required** for Bluetooth commissioning: mount `/run/dbus:/run/dbus:ro`
- **IPv6 forwarding must be disabled:** `boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 0` — if enabled, Matter devices experience up to 30-minute reachability outages
- **Project in transition:** python-matter-server is in maintenance mode; rewrite to `matter.js` in progress. Current Python version (8.x) remains stable and API-compatible.
- HA integration: Settings → Devices & Services → Matter → `ws://127.0.0.1:5580/ws`

```nix
virtualisation.oci-containers.containers.matter-server = {
  image = "ghcr.io/home-assistant-libs/python-matter-server:stable";  # or pin "8.1.2"
  extraOptions = [
    "--network=host"
    "--security-opt=label=disable"  # Required for Bluetooth/D-Bus access
  ];
  volumes = [
    "/var/lib/matter-server:/data"
    "/run/dbus:/run/dbus:ro"
  ];
};

# Required host config for Matter
networking.enableIPv6 = true;
boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 0;
```

## Verified flake input URLs

| Input | URL | Status |
|-------|-----|--------|
| nixpkgs | `github:NixOS/nixpkgs/nixos-25.11` | ✅ Verified |
| disko | `github:nix-community/disko/latest` | ✅ Verified |
| sops-nix | `github:Mic92/sops-nix` | ✅ Verified |
| agenix | `github:ryantm/agenix` | ✅ Verified |
| deploy-rs | `github:serokell/deploy-rs` | ✅ Verified |
| impermanence | `github:nix-community/impermanence` | ✅ Verified |

## Service module verification summary

| Service | `services.*` Module | Package | Approach |
|---------|---------------------|---------|----------|
| Pi-hole | ❌ Does not exist | ❌ Not packaged | Podman OCI |
| Caddy | ✅ `services.caddy` | ✅ `caddy` | Native + `withPlugins` |
| NetBird client (pebble) | ✅ `services.netbird.clients.wt0` | ✅ `netbird` | Native |
| NetBird server (VPS) | ✅ `services.netbird.server` (⚠️ sparse docs) | ✅ `netbird` | Docker Compose initially |
| Homepage | ✅ `services.homepage-dashboard` | ✅ `homepage-dashboard` | Native |
| Prometheus | ✅ `services.prometheus` | ✅ `prometheus` | Native |
| Grafana | ✅ `services.grafana` | ✅ `grafana` | Native |
| Loki | ✅ `services.loki` | ✅ `grafana-loki` | Native |
| Home Assistant | ✅ `services.home-assistant` | ✅ `home-assistant` | Podman recommended |
| Uptime Kuma | ✅ `services.uptime-kuma` | ✅ `uptime-kuma` | Native |
| Authelia | ✅ `services.authelia` | ✅ `authelia` | Native (future) |
| Mosquitto | ✅ `services.mosquitto` | ✅ `mosquitto` | Native |
| Wyoming Whisper | ✅ `services.wyoming.faster-whisper` | ✅ `wyoming-faster-whisper` | Native + ProcSubset fix |
| Wyoming Piper | ✅ `services.wyoming.piper` | ✅ `wyoming-piper` | Native |
| Wyoming OpenWakeWord | ✅ `services.wyoming.openwakeword` | ✅ `wyoming-openwakeword` | Native |
| ESPHome | ✅ `services.esphome` (buggy) | ✅ `esphome` | Podman (3 native bugs) |
| Matter Server | ✅ `services.matter-server` (broken deps) | ✅ `python-matter-server` | Podman (CHIP SDK) |

---
