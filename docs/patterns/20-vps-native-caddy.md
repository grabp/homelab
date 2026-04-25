---
kind: pattern
number: 20
tags: [vps, caddy, TLS, native]
---

# Pattern 20: Hybrid VPS — NixOS-managed Caddy + OCI NetBird containers

On the VPS, use **native NixOS Caddy** (`services.caddy`) for TLS termination rather than a Caddy or Traefik container. Native Caddy handles Let's Encrypt via HTTP-01 challenge (public IP available) and avoids adding a fourth container layer.

```nix
# machines/nixos/vps/caddy.nix
{ vars, ... }:

let domain = "netbird.${vars.domain}"; in {
  services.caddy = {
    enable = true;
    globalConfig = ''
      email ${vars.adminEmail}
    '';
    virtualHosts."${domain}".extraConfig = ''
      # Management REST API
      handle /api/* {
        reverse_proxy localhost:8080
      }
      # Management gRPC — h2c = cleartext HTTP/2 to backend
      handle /management.ManagementService/* {
        reverse_proxy h2c://localhost:8080
      }
      # Signal gRPC — separate netbirdio/signal container on port 10000
      # ⚠️ Signal is NOT merged into management as of v0.68.x.
      # Signal container maps host:10000 → container:80.
      handle /signalexchange.SignalExchange/* {
        reverse_proxy h2c://localhost:10000
      }
      # Embedded Dex IdP — served by management container at /oauth2
      # ⚠️ Path is /oauth2, NOT /idp — the binary registers Dex routes at /oauth2.
      handle /oauth2/* {
        reverse_proxy localhost:8080
      }
      # Dashboard SPA — catch-all
      handle {
        reverse_proxy localhost:3000
      }
    '';
  };
}
```

**Why native Caddy beats a Caddy container on VPS:**
- Caddy native module manages ACME state in `/var/lib/caddy` — persistent without a volume
- HTTP-01 works (public IP) — no Cloudflare plugin or DNS-01 needed
- One fewer container; native systemd management, journald logs
- `services.caddy` is the same module used on pebble — consistent configuration pattern
- coturn can read Caddy's ACME certs via group membership (`users.users.turnserver.extraGroups = ["caddy"]`)

**Source:** `services.caddy` verified in nixpkgs ✅. gRPC proxying via `h2c://` verified in production ✅. `/oauth2` path confirmed from `management/server/idp/embedded.go` source ✅.
