---
kind: pattern
number: 19
tags: [netbird, server, OCI-containers, pocket-id, VPS]
---

# Pattern 19: NetBird server via OCI containers on NixOS VPS (Pocket ID OIDC)

⚠️ **Do NOT use `services.netbird.server`** — it exists in nixpkgs but is not production-ready as of nixos-25.11 (sparse documentation, unclear option interactions). Use `virtualisation.oci-containers` on the NixOS VPS instead.

As of v0.68.x the container stack is **4 OCI containers + 1 native service**:
- `netbirdio/management:0.68.3` — REST API + gRPC (`EmbeddedIdP.Enabled = false`; uses Pocket ID as external OIDC provider)
- `netbirdio/signal:0.68.3` — peer coordination, still a **separate** image (port 10000 on host, 80 in container)
- `netbirdio/dashboard:v2.36.0` — React web UI (port 3000 on host, 80 in container)
- `ghcr.io/pocket-id/pocket-id:v1.3.1` — passkey-only OIDC provider at port 1411
- native `services.coturn` — STUN/TURN (reads Caddy ACME certs; no container needed)

⚠️ **Common image name mistake:** `netbirdio/netbird:management-latest` does **not** exist on Docker Hub. The correct image is `netbirdio/management:latest`. Signal is NOT merged into the management image as of v0.68.x.

## management.json — Pocket ID OIDC configuration

Set `EmbeddedIdP.Enabled = false` and configure `HttpConfig.OIDCConfigEndpoint` to point at Pocket ID's discovery URL. `AuthAudience` must match the OIDC client ID created in Pocket ID. `IdpManagerConfig` is replaced by environment variables (`NETBIRD_MGMT_IDP=pocketid`).

**Pocket ID OIDC client requirements:**
- **Public client: ON** — the dashboard is a browser SPA and never sends a `client_secret`; confidential client → HTTP 400 "client id or secret not provided" on token exchange
- **PKCE: ON**
- **Scopes:** `openid profile email groups` — Pocket ID does NOT support `offline_access`
- Redirect URIs: `https://<domain>/nb-auth`, `https://<domain>/nb-silent-auth`

**First login after IdP switch:** Users synced by the IDP manager arrive with `blocked=1 / pending_approval=1`. Approve via SQLite before first login:
```bash
sudo sqlite3 /var/lib/netbird-mgmt/store.db \
  "UPDATE users SET blocked=0, pending_approval=0, role='owner' WHERE id='<pocket-id-user-uuid>';"
```

```nix
# machines/nixos/vps/netbird-server.nix (relevant excerpt)
{ config, lib, pkgs, vars, ... }:
let
  domain = "netbird.${vars.domain}";
  mgmtConfigTemplate = pkgs.writeText "management.json.tmpl" (builtins.toJSON {
    Stuns = [{ Proto = "udp"; URI = "stun:${domain}:3478"; Username = null; Password = null; }];
    TURNConfig = {
      Turns = [{ Proto = "udp"; URI = "turn:${domain}:3478"; Username = "netbird"; Password = "TURN_PLACEHOLDER"; }];
      CredentialsTTL = "12h";
      Secret = "TURN_PLACEHOLDER";
      TimeBasedCredentials = true;
    };
    Signal = { Proto = "https"; URI = "${domain}:443"; Username = null; Password = null; };
    HttpConfig = {
      Address = "0.0.0.0:8080";
      OIDCConfigEndpoint = "https://pocket-id.${vars.domain}/.well-known/openid-configuration";
      AuthAudience = "<pocket-id-client-id>";  # UUID from Pocket ID OIDC client
      IdpSignKeyRefreshEnabled = true;
    };
    EmbeddedIdP.Enabled = false;  # Pocket ID is the external OIDC provider
    DataStoreEncryptionKey = "ENC_PLACEHOLDER";
    StoreConfig.Engine = "sqlite";
    Datadir = "/var/lib/netbird";
    SingleAccountModeDomain = vars.domain;
    ReverseProxy = { TrustedPeers = [ "0.0.0.0/0" ]; TrustedHTTPProxies = []; TrustedHTTPProxiesCount = 0; };
  });
in {
  sops.secrets."pocket-id/netbird-env" = { };  # NETBIRD_IDP_MGMT_EXTRA_API_TOKEN=<token>

  virtualisation.oci-containers.containers = {

    # Management REST API + gRPC — Pocket ID external OIDC, no embedded Dex
    netbird-management = {
      image = "netbirdio/management:0.68.3";
      ports = [ "127.0.0.1:8080:8080" ];
      volumes = [
        "/var/lib/netbird-mgmt:/var/lib/netbird"
        "/var/lib/netbird-mgmt/management.json:/etc/netbird/management.json:ro"
      ];
      environment = {
        NETBIRD_MGMT_IDP = "pocketid";
        NETBIRD_IDP_MGMT_EXTRA_MANAGEMENT_ENDPOINT = "https://pocket-id.${vars.domain}";
      };
      environmentFiles = [ config.sops.secrets."pocket-id/netbird-env".path ];
      cmd = [
        "--port" "8080" "--log-file" "console"
        "--disable-anonymous-metrics" "true"
        "--single-account-mode-domain" vars.domain
      ];
    };

    # Signal — peer coordination (still a separate image in v0.68.x)
    # Signal binary listens on port 80 inside the container.
    netbird-signal = {
      image = "netbirdio/signal:0.68.3";
      ports = [ "127.0.0.1:10000:80" ];
    };

    netbird-dashboard = {
      image = "netbirdio/dashboard:v2.36.0";
      ports = [ "127.0.0.1:3000:80" ];
      environment = {
        AUTH_AUTHORITY = "https://pocket-id.${vars.domain}";
        AUTH_CLIENT_ID = "<pocket-id-client-id>";   # UUID from Pocket ID OIDC client
        AUTH_AUDIENCE  = "<pocket-id-client-id>";
        # offline_access NOT supported by Pocket ID — omit it
        AUTH_SUPPORTED_SCOPES = "openid profile email groups";
        # ⚠️ MUST be relative paths — the dashboard prepends window.location.origin.
        # Full URLs ("https://domain/nb-auth") cause doubling: "https://domainhttps://domain/nb-auth".
        AUTH_REDIRECT_URI        = "/nb-auth";
        AUTH_SILENT_REDIRECT_URI = "/nb-silent-auth";
        NETBIRD_MGMT_API_ENDPOINT      = "https://${domain}";
        NETBIRD_MGMT_GRPC_API_ENDPOINT = "https://${domain}";
        USE_AUTH0 = "false";
      };
    };
  };

  # Runtime secret injection — must run before management container starts
  systemd.services.netbird-management-config = {
    description = "Generate NetBird management.json with runtime secrets";
    wantedBy = [ "podman-netbird-management.service" ];
    before   = [ "podman-netbird-management.service" ];
    after    = [ "sops-install-secrets.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.jq ];
    script = ''
      TURN="$(cat ${config.sops.secrets."netbird/turn_password".path})"
      ENC="$(cat ${config.sops.secrets."netbird/encryption_key".path})"
      jq --arg turn "$TURN" --arg enc "$ENC" \
        '.TURNConfig.Turns[0].Password = $turn
         | .TURNConfig.Secret           = $turn
         | .DataStoreEncryptionKey      = $enc' \
        ${mgmtConfigTemplate} > /var/lib/netbird-mgmt/management.json
      chmod 600 /var/lib/netbird-mgmt/management.json
    '';
  };
  systemd.services.podman-netbird-management = {
    after    = [ "netbird-management-config.service" ];
    requires = [ "netbird-management-config.service" ];
  };
}
```

## Pocket ID setup gotchas

**Setup page URL (v1.3.1):** `/login/setup` — not `/setup`. Navigating to `/setup` returns a 404 that falls through to the login redirect.

**Public client required:** The NetBird dashboard is a browser SPA. It never sends a `client_secret`. Creating the Pocket ID OIDC client as "confidential" causes Pocket ID to reject the token exchange with HTTP 400 "client id or secret not provided". Always create the client with **Public client: ON**.

**`offline_access` scope:** Not supported by Pocket ID — omit from `AUTH_SUPPORTED_SCOPES`. Use `openid profile email groups` only.

**First login after IdP switch — pending_approval:** The Pocket ID IDP manager syncs users from Pocket ID's API and pre-creates them in the management store as `blocked=1 / pending_approval=1`. The OIDC auth flow completes but the management API rejects the request with "user is pending approval". No self-service escape. Fix:
```bash
sudo sqlite3 /var/lib/netbird-mgmt/store.db \
  "UPDATE users SET blocked=0, pending_approval=0, role='owner' WHERE id='<pocket-id-uuid>';"
# No container restart needed — management reads SQLite live
```

**Source:** Verified against `netbirdio/management:0.68.3` + `pocket-id:v1.3.1` in production ✅. Image names confirmed via Docker Hub API. Pocket ID client registration from `management/server/idp/embedded.go` source ✅.
