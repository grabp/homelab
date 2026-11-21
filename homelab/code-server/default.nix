# homelab/code-server/default.nix — code-server (VS Code in browser)
#
# OCI container (lscr.io/linuxserver/code-server) with a configurable
# workspace path. Intended for editing Home Assistant configuration files
# but usable for any host directory.
#
# Auth: Kanidm OIDC via oauth2-proxy (same pattern as Homepage); code-server's
# own password is disabled (no PASSWORD/HASHED_PASSWORD → linuxserver image runs
# with auth none). Only Kanidm group homelab_admins can obtain a token.
#   Caddy (code.grab-lab.gg) → oauth2-proxy 127.0.0.1:4181 → code-server 127.0.0.1:8484
#
# Secrets (pebble): kanidm/vscode_client_secret, oauth2-proxy/vscode_env
#   (OAUTH2_PROXY_CLIENT_SECRET=<same as kanidm/vscode_client_secret>,
#    OAUTH2_PROXY_COOKIE_SECRET=<32 chars>).
{
  config,
  lib,
  vars,
  ...
}:

let
  cfg = config.my.services.codeServer;
in
{
  options.my.services.codeServer = {
    enable = lib.mkEnableOption "code-server (VS Code in browser)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8484;
      description = "code-server web port (bound to loopback, only reachable via oauth2-proxy).";
    };

    oauth2ProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 4181;
      description = "oauth2-proxy listen port (loopback) — Caddy proxies code.<domain> here.";
    };

    workspacePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/homeassistant";
      description = ''
        Host path mounted as the default workspace inside code-server.
        The path is mounted at the same location inside the container so
        absolute paths in the terminal match the host filesystem.
        Defaults to the Home Assistant config directory.
      '';
    };

    puid = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        PUID for the code-server process inside the container.
        Must have read/write access to workspacePath.
        Defaults to 0 (root) because HA config files are root-owned.
      '';
    };

    pgid = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "PGID for the code-server process. Must have access to workspacePath.";
    };
  };

  config = lib.mkIf cfg.enable {

    # OAUTH2_PROXY_CLIENT_SECRET + OAUTH2_PROXY_COOKIE_SECRET for oauth2-proxy.
    sops.secrets."oauth2-proxy/vscode_env" = {
      restartUnits = [ "podman-oauth2-proxy-vscode.service" ];
    };

    # /var/lib/code-server holds VS Code extensions and user settings.
    # Separate from workspacePath so extensions survive workspace changes.
    systemd.tmpfiles.rules = [
      "d /var/lib/code-server 0750 root root -"
    ];

    virtualisation.oci-containers.containers.code-server = {
      image = "lscr.io/linuxserver/code-server:4.146.0@sha256:49b257f0817c77358ea1779a581a37a0ed3a5af5c01abf6d2b3f47b0cdb8329a";
      # Bind to loopback — Caddy is the only consumer, no LAN exposure needed.
      ports = [ "127.0.0.1:${toString cfg.port}:8443" ];
      volumes = [
        "/var/lib/code-server:/config"
        # Same path inside and outside the container so absolute paths match.
        "${cfg.workspacePath}:${cfg.workspacePath}"
      ];
      environment = {
        TZ = vars.timeZone;
        PUID = toString cfg.puid;
        PGID = toString cfg.pgid;
        DEFAULT_WORKSPACE = cfg.workspacePath;
      };
      # No PASSWORD/HASHED_PASSWORD: authentication is done by oauth2-proxy.
    };

    # ── oauth2-proxy (Kanidm OIDC) ───────────────────────────────────────────
    # Same setup as oauth2-proxy-homepage. --network=host: upstream (code-server
    # on 127.0.0.1:${toString cfg.port}) and listen address are on the host stack.
    # WebSockets (required by code-server) are proxied by default.
    virtualisation.oci-containers.containers.oauth2-proxy-vscode = {
      image = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.6@sha256:01da265f8e371e6d3043b97829e171f3e4d53f9dc3817be15fb4fc29c92fe2a6";
      # Trailing slash required; --upstream as CLI arg (env var not reliably read).
      cmd = [ "--upstream=http://127.0.0.1:${toString cfg.port}/" ];
      environment = {
        OAUTH2_PROXY_PROVIDER = "oidc";
        OAUTH2_PROXY_OIDC_ISSUER_URL = "https://id.${vars.domain}/oauth2/openid/vscode";
        OAUTH2_PROXY_CLIENT_ID = "vscode";
        OAUTH2_PROXY_REDIRECT_URL = "https://code.${vars.domain}/oauth2/callback";
        OAUTH2_PROXY_HTTP_ADDRESS = "127.0.0.1:${toString cfg.oauth2ProxyPort}";
        OAUTH2_PROXY_EMAIL_DOMAINS = "*"; # access is restricted by the Kanidm scope map
        OAUTH2_PROXY_SCOPE = "openid profile email";
        OAUTH2_PROXY_CODE_CHALLENGE_METHOD = "S256"; # PKCE — required by Kanidm
        OAUTH2_PROXY_SKIP_PROVIDER_BUTTON = "true";
        OAUTH2_PROXY_COOKIE_SECURE = "true";
        # Lax works inside the HA iframe: ha.* and code.* are the same site.
        OAUTH2_PROXY_COOKIE_SAMESITE = "lax";
      };
      environmentFiles = [ config.sops.secrets."oauth2-proxy/vscode_env".path ];
      extraOptions = [ "--network=host" ];
    };

    systemd.services.podman-oauth2-proxy-vscode = {
      after = [ "sops-install-secrets.service" ];
      wants = [ "sops-install-secrets.service" ];
    };

    # Pattern 19: NixOS firewall reload flushes Netavark DNAT rules — restart
    # the container so its port mapping is re-registered.
    systemd.services.podman-code-server = {
      after = [ "firewall.service" ];
      partOf = [ "firewall.service" ];
    };
  };
}
