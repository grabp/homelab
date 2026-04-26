---
kind: pattern
number: 6
tags: [sops-nix, secrets]
---

# Pattern 6: sops-nix secret declaration

```nix
# In NixOS configuration module
{ config, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "cloudflare_api_token" = {
        owner = config.services.caddy.user;  # ⚠ VERIFY: check caddy user
        restartUnits = [ "caddy.service" ];
      };
      "grafana_admin_password" = {
        owner = "grafana";
      };
      "pihole/env" = {};  # KEY=VALUE format for environmentFiles
    };
  };
}
```

## `.sops.yaml`

```yaml
keys:
  - &admin age1yourkeyhere
  - &pebble age1serverkeyhere
creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
        - *admin
        - *pebble
```

**Source:** sops-nix README (github:Mic92/sops-nix) ✅. Secrets decrypted to `/run/secrets/<name>`. Use `config.sops.secrets."name".path` to reference in services.
