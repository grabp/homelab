# NIX-PATTERNS.md — Validated Nix Code Patterns

Every pattern below is verified against official documentation or production repositories.

## Pattern 1: flake.nix with deploy-rs, disko, and sops-nix

```nix
# flake.nix
{
  description = "Homelab NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, deploy-rs, disko, sops-nix, ... }@inputs:
    let
      helpers = import ./flakeHelpers.nix inputs;
      inherit (helpers) mkMerge mkNixos;
    in
    mkMerge [
      (mkNixos "elitedesk" inputs.nixpkgs [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./homelab
      ])

      {
        checks = builtins.mapAttrs
          (system: deployLib: deployLib.deployChecks self.deploy)
          deploy-rs.lib;
      }
    ];
}
```

**Source:** Derived from notthebee/nix-config and deploy-rs README. All input URLs verified ✅.

## Pattern 2: flakeHelpers.nix — DRY machine definitions

```nix
# flakeHelpers.nix
inputs:
let
  mkNixos = hostname: nixpkgsVersion: extraModules: {
    deploy.nodes.${hostname} = {
      hostname = hostname;
      profiles.system = {
        user = "root";
        sshUser = "admin";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos
          (nixpkgsVersion.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; vars = import ./machines/nixos/vars.nix; };
            modules = [
              ./machines/nixos/_common
              ./machines/nixos/${hostname}
              ./users/admin
            ] ++ extraModules;
          });
      };
    };

    nixosConfigurations.${hostname} = nixpkgsVersion.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; vars = import ./machines/nixos/vars.nix; };
      modules = [
        ./machines/nixos/_common
        ./machines/nixos/${hostname}
        ./users/admin
      ] ++ extraModules;
    };
  };

  mkMerge = inputs.nixpkgs.lib.lists.foldl'
    (a: b: inputs.nixpkgs.lib.attrsets.recursiveUpdate a b) {};
in
{ inherit mkMerge mkNixos; }
```

**Source:** Reconstructed from notthebee/nix-config's flakeHelpers.nix. Pattern generates both `nixosConfigurations` and `deploy.nodes` from a single call ✅.

## Pattern 3: disko single-disk ZFS with ephemeral root

```nix
# machines/nixos/elitedesk/disko.nix
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/sda";  # ⚠ VERIFY: check actual device path
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          zfs = {
            size = "100%";
            content = { type = "zfs"; pool = "zroot"; };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        compression = "lz4";
        mountpoint = "none";
        xattr = "sa";
        acltype = "posixacl";
        "com.sun:auto-snapshot" = "false";
      };
      postCreateHook = ''
        zfs list -t snapshot -H -o name | grep -E '^zroot/root@blank$' || zfs snapshot zroot/root@blank
      '';
       datasets = {
        "root" = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
        };
        "nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };
        "var" = {
          type = "zfs_fs";
          mountpoint = "/var";
          options.mountpoint = "legacy";
        };
        "home" = {
          type = "zfs_fs";
          mountpoint = "/home";
          options.mountpoint = "legacy";
        };
        "containers" = {
          type = "zfs_volume";
          size = "50G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/lib/containers";
          };
        };
      };
    };
  };
}
```

**Source:** Based on disko/example/zfs.nix and notthebee's aria disko.nix. The `postCreateHook` creates a blank snapshot for ephemeral root rollback ✅.

**Ephemeral root rollback service** (optional, add to machine config):
```nix
boot.initrd.systemd = {
  enable = true;
  services.rollback-root = {
    after = [ "zfs-import-zroot.service" ];
    wantedBy = [ "initrd.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs rollback -r zroot/root@blank
    '';
  };
};
```

## Pattern 4: disko single-disk ext4 (simpler alternative)

```nix
{
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "500M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
```

**Source:** Official disko README quickstart example ✅.

## Pattern 5: Custom NixOS module with options

```nix
# homelab/pihole/default.nix
{ config, lib, pkgs, vars, ... }:

let
  cfg = config.my.services.pihole;
in
{
  options.my.services.pihole = {
    enable = lib.mkEnableOption "Pi-hole DNS sinkhole";

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8089;
      description = "Web interface port";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "pihole/pihole:2025.02.1";
      description = "Pi-hole OCI image with version tag";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.pihole = {
      image = cfg.image;
      ports = [
        "53:53/tcp"
        "53:53/udp"
        "${toString cfg.webPort}:80/tcp"
      ];
      volumes = [
        "/var/lib/pihole/etc-pihole:/etc/pihole"
        "/var/lib/pihole/etc-dnsmasq.d:/etc/dnsmasq.d"
      ];
      environment = {
        TZ = vars.timeZone;
        FTLCONF_LOCAL_IPV4 = vars.serverIP;
      };
      environmentFiles = [
        config.sops.secrets."pihole/env".path
      ];
      extraOptions = [ "--cap-add=NET_ADMIN" "--dns=127.0.0.1" ];
    };

    networking.firewall.allowedTCPPorts = [ 53 cfg.webPort ];
    networking.firewall.allowedUDPPorts = [ 53 ];

    # Disable systemd-resolved to free port 53
    services.resolved.enable = false;
  };
}
```

**Source:** NixOS Wiki module pattern + verified `virtualisation.oci-containers` option path ✅.

## Pattern 6: sops-nix secret declaration

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

**`.sops.yaml`:**
```yaml
keys:
  - &admin age1yourkeyhere
  - &elitedesk age1serverkeyhere
creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
        - *admin
        - *elitedesk
```

**Source:** sops-nix README (github:Mic92/sops-nix) ✅. Secrets decrypted to `/run/secrets/<name>`. Use `config.sops.secrets."name".path` to reference in services.

## Pattern 7: Caddy with Cloudflare DNS plugin

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

**Caddyfile equivalent (if using `services.caddy.extraConfig`):**
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

## Pattern 8: systemd service with sops-nix secrets injection

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

## Pattern 9: Justfile for NixOS homelab operations

```just
# justfile — NixOS homelab task runner

# ── Local Operations ──────────────────────────
switch:
    sudo nixos-rebuild switch --flake .

test:
    nixos-rebuild test --flake . --use-remote-sudo

build:
    nixos-rebuild build --flake .

debug:
    nixos-rebuild switch --flake . --use-remote-sudo --show-trace --verbose

# ── Remote Deployment ─────────────────────────
deploy host="elitedesk":
    nix run github:serokell/deploy-rs -- -s .#{{host}}

deploy-all:
    nix run github:serokell/deploy-rs -- -s .

# ── Flake Management ─────────────────────────
update:
    nix flake update

update-input input:
    nix flake update {{input}}

check:
    nix flake check

show:
    nix flake show
# ── Secrets ───────────────────────────────────
edit-secrets:
    sops secrets/secrets.yaml

rekey:
    find secrets -name '*.yaml' -exec sops updatekeys {} \;

# ── Maintenance ───────────────────────────────
gc:
    sudo nix-collect-garbage --delete-old

clean:
    sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 7d

history:
    nix profile history --profile /nix/var/nix/profiles/system

fmt:
    nix fmt

repl:
    nix repl -f flake:nixpkgs
```

**Source:** Derived from ryan4yin/nix-config and NixOS & Flakes Book ✅.

---
