---
kind: pattern
number: 8
tags: [systemd, secrets, hardening]
---

# Pattern 8: systemd service with sops-nix secrets injection

```nix
{ config, pkgs, ... }:
{
  sops.secrets."myapp/env" = {
    owner = "myapp";
    restartUnits = [ "myapp.service" ];
  };

  systemd.services.myapp = {
    description = "My Application";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "myapp";
      EnvironmentFile = [ config.sops.secrets."myapp/env".path ];
      ExecStart = "${pkgs.myapp}/bin/myapp";
      Restart = "always";
      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/myapp" ];
    };
  };

  users.users.myapp = {
    isSystemUser = true;
    group = "myapp";
  };
  users.groups.myapp = {};
}
```

**Source:** sops-nix README + NixOS systemd service patterns ✅.
