# IDP-STRATEGY.md — Identity Provider Architecture

## Two-tier IdP design

This homelab uses two identity providers, each handling a distinct authentication domain.

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Tier 1: VPS                        Tier 2: Homelab (pebble)   │
│  ┌──────────────────────────┐        ┌──────────────────────┐   │
│  │ netbird-management       │        │ Kanidm               │   │
│  │ (embedded Dex IdP)       │        │ services.kanidm      │   │
│  │                          │        │ ~50–80 MB RAM        │   │
│  │ Handles: NetBird VPN     │        │                      │   │
│  │ auth ONLY                │        │ Handles: ALL service │   │
│  │ Device code flow         │        │ SSO (OIDC + LDAP)    │   │
│  │ ~0 extra RAM             │        │ Accessible via VPN   │   │
│  └──────────────────────────┘        │ only (not internet)  │   │
│                                      └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why two tiers, not one

**The chicken-and-egg problem:** NetBird VPN auth cannot depend on the homelab IdP,
because you need the VPN to reach the homelab — and you need the IdP to authenticate
the VPN. A single homelab IdP would create a deadlock where you can't authenticate
the VPN without being on VPN.

**The solution:**
- **Tier 1 (VPS):** Embedded Dex in the `netbird-management` container handles VPN
  authentication exclusively. It's always reachable (public IP). Zero configuration —
  auto-configures during the NetBird setup wizard.
- **Tier 2 (homelab):** Kanidm on pebble handles all service SSO. Never exposed to the
  internet — accessible only via NetBird VPN tunnel. Reduced attack surface.

**Additional benefits:**
- VPS stays lean: ~500 MB total for NetBird stack + Dex, no PostgreSQL/Redis needed
- Kanidm uses embedded SQLite + single binary (~50–80 MB RAM idle)
- Homelab has 16+ GB RAM headroom — Kanidm is negligible overhead
- VPS compromise cannot affect service credentials (Kanidm is on a different machine)

---

## Per-service authentication table

| Service | Machine | Auth Method | IdP | Notes |
|---------|---------|-------------|-----|-------|
| NetBird VPN | VPS | Device code flow | Embedded Dex | Built into `netbird-management` container |
| Grafana | pebble | Native OIDC | Kanidm | `settings."auth.generic_oauth"` |
| Vaultwarden | pebble | Native OIDC | Kanidm | Master password still required for vault decryption |
| Uptime Kuma | pebble | Caddy forward_auth | Kanidm | No native SSO support |
| Homepage | pebble | Caddy forward_auth | Kanidm | No native SSO support |
| Home Assistant | pebble | Header auth (forward_auth) | Kanidm | Via hass-auth-header or Caddy |
| Outline | boulder | Native OIDC (required) | Kanidm | **No local auth fallback — Kanidm must exist first** |
| Immich | boulder | Native OIDC | Kanidm | |
| Vikunja | boulder | Native OIDC | Kanidm | |
| Paperless-ngx | boulder | Native OIDC | Kanidm | |
| Karakeep | boulder | Native OIDC | Kanidm | |
| Actual Budget | boulder | Native OIDC | Kanidm | |
| Stirling-PDF | boulder | Native OIDC | Kanidm | |
| Jellyfin | boulder | LDAP | Kanidm | Kanidm exposes LDAP on port 636 |

---

## Tier 1: Embedded Dex (VPS)

The embedded Dex IdP has been built into the `netbird-management` container since
NetBird v0.62.0. **It requires zero configuration from us** — the setup wizard at
`https://netbird.grab-lab.gg/setup` creates the initial admin account on first run.

**Characteristics:**
- Hardcoded OIDC clients (NetBird dashboard + NetBird clients only)
- Cannot serve external applications
- Email/password auth with bcrypt hashing
- Users managed entirely in the NetBird Dashboard UI
- No CLI, no declarative provisioning — this is fine since we have only 2–3 VPN users

**Auth flow for NetBird clients:**
1. `netbird-wt0 up` triggers device code flow
2. Browser opens `https://netbird.grab-lab.gg/` → Dex login page
3. User enters email/password created in Dashboard
4. Client receives token, connects to WireGuard tunnel

---

## Tier 2: Kanidm (pebble)

Kanidm is a modern identity platform written in Rust with a first-class NixOS module
(`services.kanidm`). It provides OIDC, OAuth2, and LDAP from a single binary with an
embedded database — no PostgreSQL or Redis required.

**Key advantage: declarative OAuth2 client provisioning.** All OIDC client registrations
happen in NixOS config, not via web UI clicking. Each service module defines its own
Kanidm client in the same file as the service config (co-located, not centralized).

### NixOS configuration

```nix
# homelab/kanidm/default.nix
{ config, lib, vars, ... }:

let
  cfg = config.my.services.kanidm;
in {
  options.my.services.kanidm = {
    enable = lib.mkEnableOption "Kanidm identity provider";
  };

  config = lib.mkIf cfg.enable {
    services.kanidm = {
      enableServer = true;
      serverSettings = {
        origin = "https://id.${vars.domain}";
        domain = "id.${vars.domain}";
        # Kanidm listens on 8443 internally; Caddy proxies to it
        bindaddress = "127.0.0.1:8443";
        ldapbindaddress = "127.0.0.1:636";
        # TLS is required by Kanidm — use self-signed internally, Caddy handles public TLS
        # ⚠️ VERIFY: Caddy → Kanidm TLS setup; may need tls_client_auth or self-signed cert
      };

      # Declarative provisioning: users, groups, OAuth2 clients
      provision = {
        enable = true;
        adminPasswordFile = config.sops.secrets."kanidm/admin_password".path;
        idmAdminPasswordFile = config.sops.secrets."kanidm/idm_admin_password".path;

        persons = {
          "alice" = {
            displayName = "Alice";
            mailAddresses = [ "alice@${vars.domain}" ];
          };
        };

        groups = {
          "homelab_users" = {
            members = [ "alice" ];
          };
          "homelab_admins" = {
            members = [ "alice" ];
          };
        };

        # OAuth2 clients are defined in their respective service modules.
        # Example from homelab/grafana/default.nix:
        #
        # services.kanidm.provision.systems.oauth2."grafana" = {
        #   displayName = "Grafana";
        #   originUrl = "https://grafana.${vars.domain}/login/generic_oauth";
        #   originLanding = "https://grafana.${vars.domain}";
        #   scopeMaps."homelab_users" = [ "openid" "profile" "email" "groups" ];
        # };
      };
    };

    sops.secrets."kanidm/admin_password" = {};
    sops.secrets."kanidm/idm_admin_password" = {};

    networking.firewall.allowedTCPPorts = [ 636 ];
    # Port 8443 is NOT exposed — Caddy proxies it
  };
}
```

### Caddy virtual host for Kanidm

```nix
# In homelab/caddy/default.nix or homelab/kanidm/default.nix
services.caddy.virtualHosts."id.${vars.domain}" = {
  extraConfig = ''
    reverse_proxy localhost:8443 {
      # Kanidm requires TLS even for localhost connections
      transport http {
        tls_insecure_skip_verify
      }
    }
  '';
};
```

### OIDC issuer URL pattern

Kanidm uses **per-client issuer URLs**, not a single global issuer. Every service
must use the correct per-client discovery endpoint:

```
https://id.grab-lab.gg/oauth2/openid/<client-name>/.well-known/openid-configuration
```

This is different from most IdPs and is Kanidm's primary gotcha. Configure each
service with its specific client name.

---

## Caddy forward_auth pattern (services without native OIDC)

For services that have no OIDC support (Uptime Kuma, Homepage), Caddy acts as
an authentication proxy using Kanidm's OAuth2 authorization endpoint.

```nix
# In Caddyfile (extraConfig) for a service without native auth
"uptime.${vars.domain}" = {
  extraConfig = ''
    forward_auth localhost:8443 {
      uri /ui/oauth2/token/check
      copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }
    reverse_proxy localhost:3001
  '';
};
```

⚠️ VERIFY: Kanidm's exact forward_auth endpoint path. The `/ui/oauth2/token/check`
path is illustrative — consult Kanidm docs for the correct auth proxy endpoint.

An alternative: use **oauth2-proxy** as a sidecar between Caddy and the service,
with Kanidm as the OIDC backend. This is better-documented but adds another process.

---

## Known gotchas

| Gotcha | Detail |
|--------|--------|
| Per-client issuer URLs | Each service gets `https://id.grab-lab.gg/oauth2/openid/<name>/.well-known/...` — not a global issuer |
| PKCE S256 enforced | Disable per-client for legacy apps: `kanidm system oauth2 warning-enable-legacy-crypto <client>` |
| ES256 token signing | Kanidm signs tokens with ES256, not RS256. Most modern apps handle this, but verify each service |
| Admin is CLI-only | Web UI is end-user self-service only. Provisioning is via `kanidm` CLI or NixOS `provision` |
| TLS required internally | Kanidm requires TLS even on localhost. Use `tls_insecure_skip_verify` in Caddy transport or provision a self-signed cert |
| Kanidm must run before Outline | Outline has no local auth fallback — deployment is blocked until Kanidm is verified |

---

## Deployment order and blocking relationships

```
Stage 4 (Caddy) ──────────────────────────────────────────────────────┐
Stage 7b (NetBird client) ─────────────────────────────────────────────┼──► Stage 7c (Kanidm)
                                                                       │
Stage 7c (Kanidm) ─────────────────────────────────────────────────────┼──► Grafana OIDC
                                                                       │
Stage 7c (Kanidm) ─────────────────────────────────────────────────────┼──► Stage 16 (Outline)
                                                                       │         Immich
                                                                       │         Vikunja
                                                                       │         Paperless
                                                                       └──► etc.
```

Kanidm must be deployed and verified (at minimum: Grafana OIDC login works) before
deploying any service that requires SSO.

---

## Future: unified credentials (optional, not day-one)

Once Kanidm is stable, it can optionally be added as an external OIDC provider in
NetBird, replacing the embedded Dex for VPN auth. This gives unified credentials
(one login for everything). However it reintroduces the chicken-and-egg dependency,
so it requires a separate NetBird "bootstrap" user that authenticates via embedded Dex.

This is a future optimization — the two-tier architecture works well independently.

---

## Fallback: Authelia + LLDAP

If Kanidm proves problematic (per-client issuer URLs confuse a service, ES256 not
supported, TLS-on-localhost is difficult), the fallback is:

- **Authelia** (`services.authelia`) — OIDC provider, forward_auth middleware
- **LLDAP** (OCI container) — lightweight LDAP for Jellyfin

Combined RAM: ~35 MB. Both have NixOS modules. Authelia uses a single global issuer
URL (no per-client pattern), which is more compatible with legacy services.

The migration from Kanidm to Authelia+LLDAP would require reconfiguring each service's
OIDC settings — plan accordingly if this fallback is needed.
