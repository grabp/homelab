---
kind: pattern
number: 23
tags: [grafana, kanidm, OIDC, SSO]
---

# Pattern 23: Grafana OIDC with Kanidm

Grafana is the simplest service to test Kanidm OIDC integration — use it as the reference implementation before configuring other services.

```nix
# homelab/grafana/default.nix — verified working (nixos-25.11, kanidm 1.9, grafana 11.x)
{ config, lib, vars, ... }:
{
  services.grafana.settings = {
    server = {
      domain   = "grafana.${vars.domain}";
      root_url = "https://grafana.${vars.domain}";
    };

    # Kanidm OIDC — per-client issuer URL pattern.
    # auto_login = false until OIDC verified; flip to true after.
    "auth.generic_oauth" = {
      enabled             = true;
      name                = "Kanidm";
      client_id           = "grafana";
      # Secret is shared with Kanidm provision via basicSecretFile (single-phase deploy).
      # mode 0444 on the sops secret so grafana can read it via $__file{}.
      client_secret       = "$__file{${config.sops.secrets."kanidm/grafana_client_secret".path}}";
      auth_url            = "https://id.${vars.domain}/ui/oauth2";
      token_url           = "https://id.${vars.domain}/oauth2/token";
      api_url             = "https://id.${vars.domain}/oauth2/openid/grafana/userinfo";
      scopes              = "openid profile email groups";
      # Kanidm 1.9 enforces PKCE — required or login fails with "Invalid state"
      use_pkce            = true;
      # Kanidm returns groups as SPNs: "groupname@kanidm-domain"
      # e.g. homelab_admins@id.grab-lab.gg — NOT bare "homelab_admins"
      role_attribute_path = "contains(groups[*], 'homelab_admins@id.${vars.domain}') && 'Admin' || 'Viewer'";
      allow_sign_up       = true;
      auto_login          = false;
    };
  };

  # The grafana_client_secret is declared in kanidm/default.nix with mode=0444.
  # Redeclare here with restartUnits so Grafana restarts on secret rotation.
  # sops-nix merges duplicate declarations.
  sops.secrets."kanidm/grafana_client_secret" = {
    mode         = "0444";
    restartUnits = [ "grafana.service" ];
  };
}
```

**Verification steps:**
1. `kanidm --url https://id.grab-lab.gg system oauth2 list --name admin` — shows "grafana" client
2. Navigate to `https://grafana.grab-lab.gg` → click "Sign in with Kanidm"
3. Redirected to `https://id.grab-lab.gg` → login → redirected back to Grafana
4. Grafana user created with Admin role (if in homelab_admins group)

**Source:** Grafana `auth.generic_oauth` with `use_pkce` verified in production ✅. Kanidm groups-as-SPNs format verified in production ✅ (nixos-25.11, kanidm 1.9.x).
