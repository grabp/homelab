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

## Vaultwarden — native module, critical service

**Module status:** ✅ `services.vaultwarden` EXISTS. Options: `enable`, `package`, `config`, `backupDir`, `environmentFile`, `dbBackend`.

**Package:** `pkgs.vaultwarden`

**Ports:** 8222/tcp (remapped from default 8000/8080 for clarity)

**Secrets:** `vaultwarden/admin_token` via `environmentFile`

**Isolation:** Native NixOS module

**Resource usage:** ~50 MB RAM, negligible CPU

**Database:** SQLite (default, recommended for single-user/family use)

**SSO/Auth:** Native OIDC available via Kanidm — enable with `SSO_ENABLED = true` and `SSO_AUTHORITY = "https://id.grab-lab.gg/oauth2/openid/vaultwarden/.well-known/openid-configuration"`. Note: **master password is still required for vault decryption** regardless of SSO — this is Bitwarden's design. SSO only gates access to the web vault, not the encryption key.

**Known gotchas:**
- `backupDir` creates automatic daily SQLite backups — include this path in restic
- Admin panel at `/admin` requires `ADMIN_TOKEN` — store in sops, not plain text
- Mobile apps and browser extensions connect to `vault.grab-lab.gg` as custom server
- `SIGNUPS_ALLOWED` should be `false` after initial account creation
- `DOMAIN` must match the public URL including `https://`

**Backup strategy:** Vaultwarden is a critical service — credential loss has severe impact.
1. `backupDir` creates daily SQLite copies (automatic)
2. Include `/var/lib/vaultwarden/backups` in restic
3. Store emergency sheets offline (paper or encrypted USB)
4. Test restore procedure periodically

```nix
# homelab/vaultwarden/default.nix
{ config, lib, vars, ... }:

let
  cfg = config.my.services.vaultwarden;
in
{
  options.my.services.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden password manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8222;
      description = "Port for Vaultwarden web interface";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."vaultwarden/admin_token" = {
      owner = "vaultwarden";
      restartUnits = [ "vaultwarden.service" ];
    };

    services.vaultwarden = {
      enable = true;
      backupDir = "/var/lib/vaultwarden/backups";
      environmentFile = config.sops.secrets."vaultwarden/admin_token".path;
      config = {
        DOMAIN = "https://vault.${vars.domain}";
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = cfg.port;
        SIGNUPS_ALLOWED = false;  # Disable after initial setup
        INVITATIONS_ALLOWED = true;
        SHOW_PASSWORD_HINT = false;
        # LOG_LEVEL = "info";
      };
    };

    # Daily backup timer (built-in, but verify it's running)
    # Backups stored in /var/lib/vaultwarden/backups/

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

**Secrets file (`secrets/secrets.yaml`) entry:**
```yaml
vaultwarden/admin_token: |
  ADMIN_TOKEN=<generate-with-openssl-rand-base64-48>
```

**Caddy configuration (add to `homelab/caddy/default.nix`):**
```nix
@vault host vault.${vars.domain}
handle @vault {
  reverse_proxy localhost:${toString config.my.services.vaultwarden.port}
}
```

## NetBird — self-hosted control plane (VPS) + client (homelab)

This project self-hosts the NetBird control plane on a Hetzner CX22 VPS. The homelab (pebble) runs the NetBird client and acts as a routing peer advertising `192.168.10.0/24`. Full research: `docs/NETBIRD-SELFHOSTED.md`.

---

### NetBird server — VPS (`machines/nixos/vps/netbird-containers.nix`)

**Approach:** Podman OCI containers via `virtualisation.oci-containers` on NixOS VPS + native NixOS coturn + native NixOS Caddy for TLS. See NIX-PATTERNS.md Pattern 19 and 20 for the full implementation.

⚠️ **Do NOT use `services.netbird.server`** — the NixOS module exists but is not production-ready as of nixos-25.11. Use OCI containers instead.

**Images (since NetBird v0.62.0, as of v0.68.x):**
- `netbirdio/management:latest` — management REST API + gRPC + **embedded Dex IdP** (port 8080)
- `netbirdio/signal:latest` — peer coordination, **still a separate image** (not merged into management)
- `netbirdio/dashboard:latest` — React web UI
- native `services.coturn` — STUN/TURN (no container needed)

⚠️ **Common image name mistake:** `netbirdio/netbird:management-latest` does NOT exist on Docker Hub. The correct image is `netbirdio/management:latest`. Signal is NOT merged into management as of v0.68.x.

⚠️ **Pin image tags to specific versions before production** — `management:latest` is a rolling tag. Use `netbirdio/management:v0.68.1` (or current stable) in production.

**VPS ports:** 80/tcp (ACME HTTP-01 via Caddy), 443/tcp (Caddy: dashboard + REST API + gRPC), 3478/udp+tcp (STUN/TURN coturn), 5349/tcp (TURN TLS), 49152–65535/udp (TURN relay range)

**Secrets:** `netbird/turn_password`, `netbird/encryption_key` in `secrets/vps.yaml`

**DNS record:** A record `netbird.grab-lab.gg → 204.168.181.110` — **DNS only** in Cloudflare (gray cloud). Cloudflare proxying breaks gRPC.

**Identity provider:** Embedded Dex (built into `netbird-management` container since v0.62.0). Zero configuration — auto-configures during setup wizard at `/setup`. No Zitadel, no CockroachDB, no external IdP accounts needed.

**Architecture:**
```
Browser / NetBird clients
       ↓ HTTPS 443
  Caddy (native, services.caddy)
   ┌────┼──────────────────────────┐
   /   /api   /management…/   /signalexchange…/
        ↓            ↓
     :8080        :8080
  (combined mgmt+signal+relay OCI container)
  (embedded Dex IdP at /idp/*)
              coturn :3478/:5349 (native)
  netbird-dashboard :3000 (OCI, proxied at /)
```

**management.json secret injection:** `management.json` is generated at build time via `pkgs.writeText` (with placeholder values), then a systemd oneshot (`netbird-management-config`) uses `jq` at runtime to substitute the real sops secret values before the container starts.

**Known gotchas:**
- The setup wizard at `https://netbird.grab-lab.gg/setup` must be completed once to create the admin account (embedded Dex auto-configures on first run)
- `services.caddy.enable = true` must be set explicitly; use native Caddy (no Cloudflare plugin needed — HTTP-01 works on public VPS)
- coturn needs read access to ACME certs — `users.users.turnserver.extraGroups = ["caddy"]` (not nginx) when using native Caddy
- ⚠️ VERIFY: gRPC proxy syntax for Caddy (`reverse_proxy h2c://localhost:8080`) vs nginx (`grpc_pass grpc://127.0.0.1:8080`)
- `DataStoreEncryptionKey` from `netbird/encryption_key` secret is critical — back up this secret before migration; without it the SQLite database is unreadable

---

### NetBird client — homelab pebble (`homelab/netbird/default.nix`)

**Module status:** ✅ `services.netbird.clients.<name>` EXISTS. Module reworked in nixpkgs PR #354032.

**Package:** `pkgs.netbird`

**Ports:** 51820/udp outbound to VPS (WireGuard); no inbound ports needed (CGNAT)

**Secrets:** `netbird/setup_key` in `secrets/secrets.yaml`

**Known gotchas:**
- **`DNSStubListener=no` is required** for Pi-hole + NetBird coexistence. See Pattern 15 in `docs/NIX-PATTERNS.md`. Pi-hole holds port 53; resolved runs as routing daemon only for NetBird's `resolvectl` calls.
- ⚠️ **Management URL:** `login.managementUrl` option may exist — ⚠️ VERIFY. If not, run once manually after first deploy: `netbird-wt0 up --management-url https://netbird.grab-lab.gg --setup-key $(cat /run/secrets/netbird/setup_key)`
- **Route advertisement** (192.168.10.0/24) is configured in the NetBird Dashboard, not in NixOS. `useRoutingFeatures = "both"` enables the kernel IP forwarding prerequisite only.
- **CGNAT:** expect relay connections (~7 Mbps / ~85ms). `netbird status -d` showing `ICE candidate: relay` is normal, not a failure.
- **Stale relay bug (GitHub #3936):** connection shows "Connected" but traffic stops. Fix: `netbird-wt0 down && netbird-wt0 up`.

```nix
{ config, lib, vars, ... }:
{
  sops.secrets."netbird/setup_key" = {};

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
      setupKeyFile = config.sops.secrets."netbird/setup_key".path;
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

## Kanidm — native OIDC + LDAP identity provider (Stage 7c)

**Module status:** ✅ `services.kanidm` EXISTS with `enableServer` and `provision` submodule.

**Package:** `pkgs.kanidm`

**Ports:** 8443/tcp (HTTPS/OIDC — proxied by Caddy, not directly exposed), 636/tcp (LDAPS for Jellyfin)

**RAM:** ~50–80 MB idle

**Storage:** Embedded SQLite in `/var/lib/kanidm` — no PostgreSQL/Redis required

**Isolation:** Native NixOS module on pebble (machine 1). Accessible **only via VPN** — never exposed to the internet.

**Secrets:** Admin recovery password + idm_admin password (via sops-nix)

**Key feature:** Declarative OAuth2 client provisioning via `services.kanidm.provision` — no web UI clicking. Each service module co-locates its Kanidm client definition alongside its service config.

See `docs/IDP-STRATEGY.md` for the full two-tier IdP design rationale and per-service auth table.

**Known gotchas:**
- **Per-client issuer URLs** — not a global issuer. Each service uses `https://id.grab-lab.gg/oauth2/openid/<client-name>/.well-known/openid-configuration`
- **PKCE S256 enforced by default** — disable per-client for legacy apps: `kanidm system oauth2 warning-enable-legacy-crypto <client>`
- **ES256 token signing** (not RS256) — most apps handle this; verify per service
- **Admin is CLI-only** — web UI is end-user self-service only; all provisioning is via `services.kanidm.provision` or `kanidm` CLI
- **TLS required internally** — Kanidm binds on HTTPS even for localhost. Caddy transport needs `tls_insecure_skip_verify` or a provisioned self-signed cert
- **Kanidm must exist before Outline** — Outline has no local auth fallback; deployment is blocked until Kanidm is verified

```nix
# homelab/kanidm/default.nix
{ config, lib, vars, ... }:
let cfg = config.my.services.kanidm; in
{
  options.my.services.kanidm.enable = lib.mkEnableOption "Kanidm IdP";

  config = lib.mkIf cfg.enable {
    services.kanidm = {
      enableServer = true;
      serverSettings = {
        origin = "https://id.${vars.domain}";
        domain = "id.${vars.domain}";
        bindaddress = "127.0.0.1:8443";
        ldapbindaddress = "127.0.0.1:636";
      };
      provision = {
        enable = true;
        adminPasswordFile    = config.sops.secrets."kanidm/admin_password".path;
        idmAdminPasswordFile = config.sops.secrets."kanidm/idm_admin_password".path;
        persons."alice" = {
          displayName   = "Alice";
          mailAddresses = [ "alice@${vars.domain}" ];
        };
        groups."homelab_users".members  = [ "alice" ];
        groups."homelab_admins".members = [ "alice" ];
        # OAuth2 clients defined in each service's own module (co-located)
      };
    };

    sops.secrets."kanidm/admin_password"     = {};
    sops.secrets."kanidm/idm_admin_password" = {};

    # Caddy virtual host for id.grab-lab.gg (add in homelab/caddy/default.nix)
    # services.caddy.virtualHosts."id.${vars.domain}".extraConfig = ''
    #   reverse_proxy localhost:8443 {
    #     transport http { tls_insecure_skip_verify }
    #   }
    # '';

    networking.firewall.allowedTCPPorts = [ 636 ];
    # 8443 NOT opened — proxied by Caddy
  };
}
```

**Verification steps:**
- `systemctl status kanidm` — active
- `kanidm system oauth2 list` — shows all provisioned OAuth2 clients
- `https://id.grab-lab.gg` — loads Kanidm self-service UI
- Grafana OIDC login works (Stage 7c acceptance test)

## Homepage Dashboard — native module with structured config

**Module status:** ✅ `services.homepage-dashboard` EXISTS. Options: `enable`, `services`, `bookmarks`, `widgets`, `settings`, `listenPort`, `environmentFile`, `allowedHosts`.

**Package:** `pkgs.homepage-dashboard`

**Ports:** 3010/tcp (remapped from default 3000 to avoid Grafana conflict)

**Secrets:** API keys for service widgets via `environmentFile`

**Isolation:** Native NixOS module

**SSO/Auth:** Caddy `forward_auth` via Kanidm (see NIX-PATTERNS.md Pattern 22). Homepage has no native auth — Caddy enforces authentication at the reverse proxy layer.

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

**SSO/Auth:** Native OIDC via Kanidm (`settings."auth.generic_oauth"`). See NIX-PATTERNS.md Pattern 23 for the full Grafana OIDC + Kanidm config. Issuer URL: `https://id.grab-lab.gg/oauth2/openid/grafana/.well-known/openid-configuration`.

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

**SSO/Auth:** Caddy `forward_auth` via Kanidm (see NIX-PATTERNS.md Pattern 22). HA has no native OIDC support — authentication is proxied at the Caddy layer. Internal HA users still exist for local/LAN access. ⚠️ VERIFY: forward_auth with HA's trusted proxies config — `http.use_x_forwarded_for: true` and `trusted_proxies: [127.0.0.1]` must be set.

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

**SSO/Auth:** Caddy `forward_auth` via Kanidm (see NIX-PATTERNS.md Pattern 22). Uptime Kuma has no native OIDC/SSO support — auth is enforced at the Caddy reverse proxy layer.

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
| Vaultwarden | ✅ `services.vaultwarden` | ✅ `vaultwarden` | Native |
| Kanidm | ✅ `services.kanidm` | ✅ `kanidm` | Native (pebble, VPN-only) |
| NetBird client (pebble) | ✅ `services.netbird.clients.wt0` | ✅ `netbird` | Native |
| NetBird server (VPS) | ⚠️ exists but NOT production-ready | ✅ `netbird` | **Podman OCI** (`netbirdio/netbird:management-latest`, dashboard) + native coturn/Caddy |
| Homepage | ✅ `services.homepage-dashboard` | ✅ `homepage-dashboard` | Native |
| Prometheus | ✅ `services.prometheus` | ✅ `prometheus` | Native |
| Grafana | ✅ `services.grafana` | ✅ `grafana` | Native |
| Loki | ✅ `services.loki` | ✅ `grafana-loki` | Native |
| Home Assistant | ✅ `services.home-assistant` | ✅ `home-assistant` | Podman recommended |
| Uptime Kuma | ✅ `services.uptime-kuma` | ✅ `uptime-kuma` | Native |
| Authelia | ✅ `services.authelia` | ✅ `authelia` | Fallback if Kanidm proves problematic (see docs/IDP-STRATEGY.md) |
| Mosquitto | ✅ `services.mosquitto` | ✅ `mosquitto` | Native |
| Wyoming Whisper | ✅ `services.wyoming.faster-whisper` | ✅ `wyoming-faster-whisper` | Native + ProcSubset fix |
| Wyoming Piper | ✅ `services.wyoming.piper` | ✅ `wyoming-piper` | Native |
| Wyoming OpenWakeWord | ✅ `services.wyoming.openwakeword` | ✅ `wyoming-openwakeword` | Native |
| ESPHome | ✅ `services.esphome` (buggy) | ✅ `esphome` | Podman (3 native bugs) |
| Matter Server | ✅ `services.matter-server` (broken deps) | ✅ `python-matter-server` | Podman (CHIP SDK) |

---
