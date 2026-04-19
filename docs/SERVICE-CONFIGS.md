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

**Images (as of v0.68.x):**
- `netbirdio/management:0.68.3` — management REST API + gRPC (`EmbeddedIdP.Enabled = false`; external OIDC via Pocket ID)
- `netbirdio/signal:0.68.3` — peer coordination, **still a separate image** (not merged into management)
- `netbirdio/dashboard:v2.36.0` — React web UI
- `ghcr.io/pocket-id/pocket-id:v1.3.1` — passkey-only OIDC provider for NetBird auth
- native `services.coturn` — STUN/TURN (no container needed)

⚠️ **Common image name mistake:** `netbirdio/netbird:management-latest` does NOT exist on Docker Hub. The correct image is `netbirdio/management:latest`. Signal is NOT merged into management as of v0.68.x.

⚠️ **Pin image tags to specific versions before production** — `management:latest` is a rolling tag. Use `netbirdio/management:v0.68.1` (or current stable) in production.

**VPS ports:** 80/tcp (ACME HTTP-01 via Caddy), 443/tcp (Caddy: dashboard + REST API + gRPC), 3478/udp+tcp (STUN/TURN coturn), 5349/tcp (TURN TLS), 49152–65535/udp (TURN relay range)

**Secrets:** `netbird/turn_password`, `netbird/encryption_key` in `secrets/vps.yaml`

**DNS record:** A record `netbird.grab-lab.gg → 204.168.181.110` — **DNS only** in Cloudflare (gray cloud). Cloudflare proxying breaks gRPC.

**Identity provider:** Pocket ID (`ghcr.io/pocket-id/pocket-id:v1.3.1`) — passkey-only OIDC, separate OCI container at `https://pocket-id.grab-lab.gg`. `EmbeddedIdP.Enabled = false` in `management.json`. No passwords — WebAuthn/FIDO2 only.

**Architecture:**
```
Browser / NetBird clients
       ↓ HTTPS 443
  Caddy (native, services.caddy)
   ┌────┼──────────────────────────────────────────────┐
   /   /api   /management…/   /signalexchange…/   pocket-id.*
        ↓            ↓                                 ↓
     :8080        :10000                             :1411
  netbird-mgmt     netbird-signal                 pocket-id
  (no embedded Dex)
              coturn :3478/:5349 (native)
  netbird-dashboard :3000 (OCI, proxied at /)
```

**management.json secret injection:** `management.json` is generated at build time via `pkgs.writeText` (with placeholder values), then a systemd oneshot (`netbird-management-config`) uses `jq` at runtime to substitute the real sops secret values before the container starts.

**Known gotchas:**
- Pocket ID setup: browse to `https://pocket-id.grab-lab.gg/login/setup` (v1.3.1 path); OIDC client must be **Public** (not confidential); `offline_access` scope unsupported — use `openid profile email groups`
- After IdP switch: new users are synced as `blocked=1/pending_approval=1`; approve via `sqlite3 /var/lib/netbird-mgmt/store.db "UPDATE users SET blocked=0,pending_approval=0,role='owner' WHERE id='<uuid>';"` before first login
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

**Package:** `pkgs.kanidmWithSecretProvisioning_1_9` (**not** `pkgs.kanidm`)

⚠️ nixos-25.11 `services.kanidm` module defaults to `pkgs.kanidm_1_4` which is EOL and removed from nixpkgs. Must set `services.kanidm.package = pkgs.kanidmWithSecretProvisioning_1_9` explicitly. `_1_7` is also gone (marked insecure).

**Ports:** 8443/tcp (HTTPS/OIDC — proxied by Caddy, not directly exposed), 636/tcp (LDAPS for Jellyfin)

**RAM:** ~50–80 MB idle

**Storage:** Embedded SQLite in `/var/lib/kanidm` — no PostgreSQL/Redis required

**Isolation:** Native NixOS module on pebble (machine 1). Accessible **only via VPN** — never exposed to the internet.

**Secrets:** Admin recovery password + idm_admin password (via sops-nix)

**Key feature:** Declarative OAuth2 client provisioning via `services.kanidm.provision` — no web UI clicking. Each service module co-locates its Kanidm client definition alongside its service config.

See `docs/IDP-STRATEGY.md` for the full two-tier IdP design rationale and per-service auth table.

**Known gotchas:**
- **`kanidm_1_4` removed** — nixos-25.11 module default is gone. Explicitly set `package = pkgs.kanidmWithSecretProvisioning_1_9`.
- **"admin" username reserved** — Kanidm has a built-in system account named `admin`. Provisioning a person named `admin` → 409 Conflict. Use a distinct username (e.g. the person's actual login name).
- **sops secret ownership for provisioning** — the provisioning `ExecStartPost` runs as the `kanidm` user. Password secrets need `owner = "kanidm"` or provisioning fails with "permission denied". The OAuth2 `basicSecretFile` secret needs `mode = "0444"` (world-readable for grafana too).
- **Self-signed cert must have `CA:FALSE`** — Kanidm 1.9 strict TLS rejects OpenSSL default self-signed certs (`CaUsedAsEndEntity` error). Generate with `-addext "basicConstraints=CA:FALSE" -addext "subjectAltName=IP:127.0.0.1,DNS:id.<domain>"`.
- **`enableClient = true` requires `clientSettings`** — module enforces this. Add CLI to PATH via `environment.systemPackages = [ pkgs.kanidmWithSecretProvisioning_1_9 ]` instead.
- **PKCE enforced by default** — Kanidm 1.9 requires PKCE on all clients. Grafana needs `use_pkce = true` in `"auth.generic_oauth"`. Other services similarly.
- **Groups returned as SPNs** — the `groups` OIDC claim contains full SPNs: `groupname@kanidm-domain` (e.g. `homelab_admins@id.grab-lab.gg`). Role mappings must use the full SPN, not bare group names.
- **Per-client issuer URLs** — not a global issuer. Each service uses `https://id.grab-lab.gg/oauth2/openid/<client-name>/.well-known/openid-configuration`
- **ES256 token signing** (not RS256) — most apps handle this; verify per service
- **Admin is CLI-only** — web UI is end-user self-service only; all provisioning is via `services.kanidm.provision` or `kanidm` CLI
- **TLS required internally** — Kanidm binds on HTTPS even for localhost. Caddy transport needs `tls_insecure_skip_verify`
- **Kanidm must exist before Outline** — Outline has no local auth fallback; deployment is blocked until Kanidm is verified

```nix
# homelab/kanidm/default.nix — verified working pattern (Stage 7c)
{ config, lib, pkgs, vars, ... }:
let cfg = config.my.services.kanidm; in
{
  options.my.services.kanidm.enable = lib.mkEnableOption "Kanidm IdP";

  config = lib.mkIf cfg.enable {
    # CLI in PATH without enableClient (which requires clientSettings)
    environment.systemPackages = [ pkgs.kanidmWithSecretProvisioning_1_9 ];

    # Regenerate self-signed cert if missing or has CA:TRUE (old bad default)
    systemd.services.kanidm-tls-cert = {
      description = "Generate Kanidm self-signed TLS certificate";
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ pkgs.openssl ];
      script = ''
        install -d -m 750 -o kanidm -g kanidm /var/lib/kanidm
        needs_regen=0
        [ ! -f /var/lib/kanidm/tls.pem ] && needs_regen=1
        if [ -f /var/lib/kanidm/tls.pem ]; then
          openssl x509 -in /var/lib/kanidm/tls.pem -noout -text 2>/dev/null \
            | grep -q "CA:TRUE" && needs_regen=1
        fi
        if [ "$needs_regen" = "1" ]; then
          openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
            -keyout /var/lib/kanidm/tls.key -out /var/lib/kanidm/tls.pem \
            -days 3650 -nodes -subj '/CN=id.${vars.domain}' \
            -addext "basicConstraints=CA:FALSE" \
            -addext "subjectAltName=IP:127.0.0.1,DNS:id.${vars.domain}"
          chown kanidm:kanidm /var/lib/kanidm/tls.key /var/lib/kanidm/tls.pem
          chmod 600 /var/lib/kanidm/tls.key && chmod 644 /var/lib/kanidm/tls.pem
        fi
      '';
    };
    systemd.services.kanidm = {
      requires = [ "kanidm-tls-cert.service" ];
      after    = [ "kanidm-tls-cert.service" ];
    };

    services.kanidm = {
      enableServer = true;
      package = pkgs.kanidmWithSecretProvisioning_1_9;  # 1_4 is EOL/removed
      serverSettings = {
        origin          = "https://id.${vars.domain}";
        domain          = "id.${vars.domain}";
        bindaddress     = "127.0.0.1:8443";
        ldapbindaddress = "127.0.0.1:636";
        tls_chain       = "/var/lib/kanidm/tls.pem";
        tls_key         = "/var/lib/kanidm/tls.key";
      };
      provision = {
        enable             = true;
        instanceUrl        = "https://127.0.0.1:8443";
        acceptInvalidCerts = true;
        # owner = "kanidm" required — provisioning runs as kanidm user
        adminPasswordFile    = config.sops.secrets."kanidm/admin_password".path;
        idmAdminPasswordFile = config.sops.secrets."kanidm/idm_admin_password".path;
        # NOTE: "admin" is reserved — use a distinct person username
        persons."yourname" = {
          displayName   = "Your Name";
          mailAddresses = [ "admin@${vars.domain}" ];
        };
        groups."homelab_users".members  = [ "yourname" ];
        groups."homelab_admins".members = [ "yourname" ];
      };
    };

    # owner = "kanidm": provisioning post-start runs as kanidm user
    sops.secrets."kanidm/admin_password"     = { owner = "kanidm"; };
    sops.secrets."kanidm/idm_admin_password" = { owner = "kanidm"; };
    # mode 0444: readable by both kanidm provisioning and grafana ($__file{})
    sops.secrets."kanidm/grafana_client_secret" = { mode = "0444"; };

    networking.firewall.allowedTCPPorts = [ 636 ];
    # 8443 NOT opened — Caddy proxies via localhost
  };
}
```

**Setting a person's login password (post-deploy):**
```bash
# CLI is in PATH via environment.systemPackages
kanidm --url https://id.grab-lab.gg login --name idm_admin
# (password: sudo cat /run/secrets/kanidm/idm_admin_password)
kanidm --url https://id.grab-lab.gg person credential create-reset-token <username>
# open the printed URL in browser to set password
```

**Verification steps:**
- `systemctl status kanidm kanidm-tls-cert` — both active
- `kanidm --url https://id.grab-lab.gg system oauth2 list --name admin` — shows provisioned clients
- `https://id.grab-lab.gg` — loads Kanidm self-service UI
- Grafana OIDC login works with Admin role (Stage 7c acceptance test ✅)

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
- **`allowedHosts` is required when accessed via a reverse proxy** — without it Homepage returns 403. Set it to the public hostname (e.g. `"home.grab-lab.gg"`).
- Services without a web UI (e.g. Caddy) should omit `href` entirely — Homepage renders them as non-clickable informational tiles
- Use `environmentFile` for API tokens referenced in widget config as `{{HOMEPAGE_VAR_NAME}}`

```nix
services.homepage-dashboard = {
  enable = true;
  listenPort = 3010;
  allowedHosts = "home.grab-lab.gg";  # required for reverse-proxy access
  settings = {
    title       = "Homelab";
    headerStyle = "clean";
    target      = "_blank";
  };
  services = [
    {
      "Infrastructure" = [
        { "Pi-hole" = { href = "https://pihole.grab-lab.gg"; description = "DNS sinkhole"; icon = "pi-hole.svg"; }; }
        { "Caddy"   = {                                       description = "Reverse proxy + TLS"; icon = "caddy.svg"; }; }
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
- **PKCE required for Kanidm 1.9**: set `use_pkce = true` in `"auth.generic_oauth"` or login fails with "Invalid state / No PKCE code challenge"
- **Groups claim uses SPNs**: Kanidm returns `homelab_admins@id.grab-lab.gg`, not `homelab_admins`. `role_attribute_path` must match the full SPN: `contains(groups[*], 'homelab_admins@id.grab-lab.gg') && 'Admin' || 'Viewer'`

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
- `compactor.delete_request_store = "filesystem"` is **required** when `retention_enabled = true` — Loki rejects the config otherwise (verified in Stage 6)

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

### Log shippers — use Alloy, not Promtail

⚠️ **Promtail is EOL as of 2026-03-02.** Grafana has ended commercial support and will not issue
future updates. **Do not add new promtail instances.** Use `services.alloy` instead.

- `services.alloy` exists in nixpkgs (verified: alloy 5.1.0 in nixos-25.11)
- Options: `enable`, `configPath`, `environmentFile`, `extraFlags`, `package`
- Alloy uses River/Alloy syntax (`.alloy` files), not YAML

**Alloy config for journald → Loki (local, single-machine):**
```nix
services.alloy = {
  enable = true;
  configPath = "/etc/alloy/config.alloy";
};

environment.etc."alloy/config.alloy".text = ''
  loki.source.journal "journal" {
    max_age       = "12h"
    relabel_rules = loki.relabel.labels.rules
    forward_to    = [loki.write.local.receiver]
  }

  loki.relabel "labels" {
    forward_to = []
    rule {
      source_labels = ["__journal__systemd_unit"]
      target_label  = "unit"
    }
    rule {
      replacement  = "pebble"   # change per host
      target_label = "host"
    }
    rule {
      replacement  = "systemd-journal"
      target_label = "job"
    }
  }

  loki.write "local" {
    endpoint {
      url = "http://localhost:3100/loki/api/v1/push"
    }
  }
'';

systemd.tmpfiles.rules = [ "d /var/lib/alloy 0750 alloy alloy -" ];
```

### Multi-machine log shipping (VPS → pebble)

**TODO:** VPS logs are not currently shipped to Loki. See `docs/VPS-LOKI-SHIPPING.md` for the
full implementation plan and safety analysis.

**Summary:** Run `services.alloy` on the VPS; push logs over the NetBird mesh to
`http://<pebble-netbird-ip>:3100/loki/api/v1/push`. Requires:
1. Loki `http_listen_address` changed from `127.0.0.1` to `0.0.0.0`
2. `networking.firewall.interfaces."wt0".allowedTCPPorts = [ 3100 ]` on pebble (NetBird interface only)
3. `machines/nixos/vps/monitoring.nix` with Alloy config

See `docs/VPS-LOKI-SHIPPING.md` for the complete implementation plan.

## Home Assistant — native module exists but OCI recommended

**Module status:** ✅ `services.home-assistant` EXISTS. Options: `enable`, `config`, `configDir`, `package`, `extraComponents`, `extraPackages`, `customComponents`.

**Package:** `pkgs.home-assistant`

**Ports:** 8123/tcp; 21064+/tcp per HomeKit bridge (21064 first bridge, 21065 second, etc.)

**Secrets:** HA manages its own secrets via `secrets.yaml`

**Isolation:** Podman OCI container recommended (upstream considers NixOS unsupported; HA version freezes at branch-off)

**SSO/Auth:** Caddy `forward_auth` via Kanidm (see NIX-PATTERNS.md Pattern 22). HA has no native OIDC support — authentication is proxied at the Caddy layer. Internal HA users still exist for local/LAN access. ⚠️ VERIFY: forward_auth with HA's trusted proxies config — `http.use_x_forwarded_for: true` and `trusted_proxies: [127.0.0.1]` must be set.

**Known gotchas:**
- Running natively: HA version freezes at NixOS release branch-off and misses updates. Consider nixpkgs-unstable overlay for latest version.
- Container approach needs `--network=host` for mDNS device discovery (Zigbee, Chromecast, etc.)
- UniFi integration requires a **local admin user** on UniFi controller (not SSO account)
- Configure `http.use_x_forwarded_for: true` and `trusted_proxies: [127.0.0.1]` for Caddy reverse proxy
- HA onboarding is interactive — not fully declarative
- **HomeKit bridge:** each bridge instance needs its TCP port open in the firewall (21064 for the first, 21065 for the second, etc.). mDNS (`_hap._tcp`) is advertised by Avahi automatically via `--network=host`, but pairing will silently fail if the HAP port is blocked. Use `my.services.homeAssistant.homekitPorts = [ 21064 21065 ]` in the machine config.

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
| Alloy (log shipper) | ✅ `services.alloy` | ✅ `alloy` (5.1.0) | Native — replaces EOL Promtail |
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
