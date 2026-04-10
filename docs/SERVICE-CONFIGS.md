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

## NetBird — native module with comprehensive options

**Module status:** ✅ `services.netbird` EXISTS. Client: `services.netbird.clients.<name>`. Server: `services.netbird.server` (~90 options across 22 option sets).

**Package:** `pkgs.netbird`

**Ports:** 51821/udp (WireGuard, configurable), outbound HTTPS (443) to control plane, STUN 3478/udp

**Secrets:** Setup key via `setupKeyFile`

**Isolation:** Native NixOS module

**Known gotchas:**
- **Requires `services.resolved.enable = true`** for DNS to work — conflicts with Pi-hole which needs `resolved` disabled. Resolution: bind Pi-hole to the host's LAN IP only (`192.168.10.X:53`), let `systemd-resolved` handle the loopback (`127.0.0.53:53`), and configure resolved to forward to Pi-hole.
- ⚠ **VERIFY:** The coexistence of `systemd-resolved` + Pi-hole + NetBird on the same host requires careful DNS binding configuration. Test this thoroughly.
- Module changed from `services.netbird.enable` to `services.netbird.clients.<name>` pattern
- `useRoutingFeatures = "both"` required for advertising LAN routes to VPN peers
- Configure Pi-hole as DNS nameserver in NetBird dashboard for VPN clients

```nix
services.netbird.clients.wt0 = {
  port = 51821;
  login = {
    enable = true;
    setupKeyFile = config.sops.secrets."netbird/setup-key".path;
  };
  ui.enable = false;
  openFirewall = true;
};
services.netbird.useRoutingFeatures = "both";
```

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
| NetBird | ✅ `services.netbird` | ✅ `netbird` | Native |
| Homepage | ✅ `services.homepage-dashboard` | ✅ `homepage-dashboard` | Native |
| Prometheus | ✅ `services.prometheus` | ✅ `prometheus` | Native |
| Grafana | ✅ `services.grafana` | ✅ `grafana` | Native |
| Loki | ✅ `services.loki` | ✅ `grafana-loki` | Native |
| Home Assistant | ✅ `services.home-assistant` | ✅ `home-assistant` | Podman recommended |
| Uptime Kuma | ✅ `services.uptime-kuma` | ✅ `uptime-kuma` | Native |
| Authelia | ✅ `services.authelia` | ✅ `authelia` | Native (future) |

---
