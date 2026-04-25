---
kind: pattern
number: 7
tags: [caddy, cloudflare, TLS]
---

# Pattern 7: Caddy with Cloudflare DNS plugin

```nix
# homelab/caddy/default.nix
{ config, pkgs, vars, ... }:
{
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.0.0-20240703190432-89f16b99c18e" ];
      hash = "";  # Build once with "" to get correct hash from error
    };
    globalConfig = ''
      email ${vars.adminEmail}
    '';
  };

  # Inject Cloudflare API token
  systemd.services.caddy.serviceConfig.EnvironmentFile = [
    config.sops.secrets."caddy/env".path
  ];

  # Secrets file (caddy/env) should contain:
  # CLOUDFLARE_API_TOKEN=your_token_here

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

## Caddyfile equivalent (if using `services.caddy.extraConfig`)

```nix
services.caddy.extraConfig = ''
  *.${vars.domain} {
    tls {
      dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      resolvers 1.1.1.1
    }

    @grafana host grafana.${vars.domain}
    handle @grafana {
      reverse_proxy localhost:3000
    }

    @ha host ha.${vars.domain}
    handle @ha {
      reverse_proxy localhost:8123
    }

    handle {
      respond "Service not found" 404
    }
  }
'';
```

**Source:** `pkgs.caddy.withPlugins` added via nixpkgs PR #358586, available since NixOS 25.05 ✅. The `resolvers 1.1.1.1` directive is critical — prevents Pi-hole from intercepting ACME DNS challenge queries.

⚠ **VERIFY:** The caddy-dns/cloudflare plugin version tag. Use the latest commit from github.com/caddy-dns/cloudflare. Set `hash = ""` on first build to get the correct SRI hash from the build error.
