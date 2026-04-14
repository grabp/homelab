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
      (mkNixos "pebble" inputs.nixpkgs [
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
# machines/nixos/pebble/disko.nix
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
  - &pebble age1serverkeyhere
creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
        - *admin
        - *pebble
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
deploy host="pebble":
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

## Pattern 10: Native Wyoming service with systemd ProcSubset override

The `wyoming-faster-whisper` NixOS module applies systemd hardening with `ProcSubset=pid`, which blocks CTranslate2 from reading `/proc/cpuinfo`. This forces a slow fallback code path — inference is ~7× slower. Always override with `lib.mkForce`. Same pattern applies if other Wyoming services ever exhibit similar hardening issues.

```nix
# homelab/wyoming/default.nix
{ config, lib, pkgs, vars, ... }:

{
  # === Speech-to-text (Faster-Whisper) ===
  services.wyoming.faster-whisper.servers."main" = {
    enable = true;
    uri = "tcp://0.0.0.0:10300";
    model = "small-int8";   # Best latency/accuracy on Ryzen + 16 GB
    language = "en";
    device = "cpu";         # CUDA not available in nixpkgs CTranslate2
  };

  # CRITICAL: Override systemd ProcSubset hardening (nixpkgs PR #372898)
  # Without this, CTranslate2 cannot read /proc/cpuinfo and falls back
  # to a slow code path — a 3-second clip takes ~20 s instead of ~3 s.
  systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset =
    lib.mkForce "all";

  # === Text-to-speech (Piper) ===
  services.wyoming.piper.servers."main" = {
    enable = true;
    uri = "tcp://0.0.0.0:10200";
    voice = "en_US-lessac-medium";   # ~65 MB, auto-downloads from HuggingFace
  };

  # === Wake word detection (OpenWakeWord) — single instance, no servers.<name> ===
  services.wyoming.openwakeword = {
    enable = true;
    uri = "tcp://0.0.0.0:10400";
    preloadModels = [ "okay_nabu" ];
    # ⚠️ VERIFY: use "ok_nabu" if nixpkgs ships wyoming-openwakeword < v2.0.0
  };

  networking.firewall.allowedTCPPorts = [ 10200 10300 10400 ];
}
```

**Source:** NixOS module source at `nixos/modules/services/home-automation/wyoming/`. ProcSubset bug confirmed in nixpkgs PR #372898. `lib.mkForce` pattern is standard NixOS for overriding hardened defaults ✅.

---

## Pattern 11: HACS auto-installation via systemd oneshot

HACS is a custom component (Python files) placed in the HA config directory — it is not a NixOS package. Since HA's config directory is bind-mounted from the host, a systemd oneshot service can install HACS before HA starts on every fresh deployment.

Two approaches are shown. **Approach A** (downloads latest on first boot) is simpler. **Approach B** (pinned version, Nix-pure) is reproducible and avoids network access at boot.

```nix
# Approach A: download latest on first boot (idempotent)
{ config, pkgs, lib, ... }:

let
  haConfigDir = "/var/lib/homeassistant";
in {
  systemd.tmpfiles.rules = [
    "d ${haConfigDir}                    0755 root root -"
    "d ${haConfigDir}/custom_components  0755 root root -"
  ];

  systemd.services.hacs-install = {
    description = "Install HACS custom component for Home Assistant";
    wantedBy    = [ "multi-user.target" ];
    before      = [ "podman-homeassistant.service" ];
    requiredBy  = [ "podman-homeassistant.service" ];
    path        = with pkgs; [ wget unzip coreutils ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      HACS_DIR="${haConfigDir}/custom_components/hacs"
      if [ ! -f "$HACS_DIR/__init__.py" ]; then
        echo "Installing HACS..."
        wget -q -O /tmp/hacs.zip \
          "https://github.com/hacs/integration/releases/latest/download/hacs.zip"
        rm -rf "$HACS_DIR"
        mkdir -p "$HACS_DIR"
        unzip -o /tmp/hacs.zip -d "$HACS_DIR"
        rm -f /tmp/hacs.zip
        echo "HACS installed."
      else
        echo "HACS already present, skipping."
      fi
    '';
  };
}
```

```nix
# Approach B: pinned version, evaluated at build time (no network at boot)
{ config, pkgs, lib, ... }:

let
  haConfigDir = "/var/lib/homeassistant";
  hacsVersion = "2.0.5";
  hacsSrc = pkgs.fetchurl {
    url    = "https://github.com/hacs/integration/releases/download/${hacsVersion}/hacs.zip";
    sha256 = "0000000000000000000000000000000000000000000000000000";
    # ⚠️ VERIFY: compute with:
    # nix-prefetch-url https://github.com/hacs/integration/releases/download/2.0.5/hacs.zip
  };
  hacsUnpacked = pkgs.runCommand "hacs-${hacsVersion}" {
    buildInputs = [ pkgs.unzip ];
  } ''
    mkdir -p $out
    unzip ${hacsSrc} -d $out
  '';
in {
  system.activationScripts.hacs = ''
    mkdir -p ${haConfigDir}/custom_components/hacs
    rm -rf   ${haConfigDir}/custom_components/hacs/*
    cp -r ${hacsUnpacked}/* ${haConfigDir}/custom_components/hacs/
    chmod -R u+w ${haConfigDir}/custom_components/hacs
  '';
}
```

**Post-install:** After HACS files are in place and HA starts, complete HACS setup in HA UI: Settings → Devices & Services → Add Integration → HACS → complete GitHub OAuth device flow. HACS works fully for custom integrations, Lovelace cards, and themes. The HA Add-on store is unavailable in container installs (requires HA OS/Supervised).

**Source:** HACS GitHub repo + sops-nix README pattern for systemd oneshot services ✅. Approach B uses standard `pkgs.fetchurl` + `pkgs.runCommand` Nix derivation patterns ✅.

---

## Pattern 12: Multi-machine flake with deploy-rs (homelab + VPS)

Extend the existing `mkNixos`/`mkMerge` helpers (Pattern 2) to manage both `pebble` (homelab) and `vps` (NetBird control plane). Each call to `mkNixos` produces one `nixosConfigurations` entry and one `deploy.nodes` entry; `mkMerge` combines them.

```nix
# flake.nix
{
  description = "Homelab NixOS configuration — pebble (homelab) + vps (NetBird)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    deploy-rs = { url = "github:serokell/deploy-rs"; inputs.nixpkgs.follows = "nixpkgs"; };
    disko    = { url = "github:nix-community/disko/latest"; inputs.nixpkgs.follows = "nixpkgs"; };
    sops-nix = { url = "github:Mic92/sops-nix"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = { self, nixpkgs, deploy-rs, disko, sops-nix, ... }@inputs:
    let
      helpers = import ./flakeHelpers.nix inputs;
      inherit (helpers) mkMerge mkNixos;
    in
    mkMerge [
      # Homelab: ZFS, all services, sops
      (mkNixos "pebble" inputs.nixpkgs [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./homelab
        ./modules/networking
      ])

      # VPS: minimal, NetBird control plane, sops
      (mkNixos "vps" inputs.nixpkgs [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        # No ./homelab — VPS runs only NetBird server, no homelab services
      ])

      {
        checks = builtins.mapAttrs
          (system: deployLib: deployLib.deployChecks self.deploy)
          deploy-rs.lib;
      }
    ];
}
```

The `mkNixos` helper in `flakeHelpers.nix` must be updated so the VPS deploy node uses the correct `sshUser` and `hostname`:

```nix
# flakeHelpers.nix — relevant section for vps node
mkNixos = hostname: nixpkgsVersion: extraModules: {
  deploy.nodes.${hostname} = {
    hostname = if hostname == "vps" then "netbird.grab-lab.gg" else hostname;
    profiles.system = {
      user    = "root";
      sshUser = "admin";
      path    = inputs.deploy-rs.lib.x86_64-linux.activate.nixos
        (nixpkgsVersion.lib.nixosSystem { ... });
    };
  };
  # ...
};
```

**Source:** Extends Pattern 2. `mkMerge` via `lib.attrsets.recursiveUpdate` + `foldl'` correctly merges attrsets from both machine calls ✅.

---

## Pattern 13: nixos-anywhere VPS provisioning with minimal ext4 disko

`nixos-anywhere` kexec-boots into a NixOS installer in RAM, partitions via disko, and installs your flake — all from one SSH command. Requires ≥1 GB RAM on the target. Works on Hetzner, DigitalOcean, Vultr, and any VPS offering root SSH access.

```bash
# Initial provisioning (run from dev machine after creating VPS)
nix run github:nix-community/nixos-anywhere -- --flake .#vps root@<VPS_IP>

# Subsequent updates via deploy-rs
nix run github:serokell/deploy-rs -- -s .#vps
# or via justfile:
# just deploy-vps
```

```nix
# machines/nixos/vps/disko.nix — simple ext4, no ZFS needed on VPS
{
  disko.devices.disk.main = {
    device = "/dev/sda";  # ⚠️ VERIFY: Hetzner CX22 uses /dev/sda; check with lsblk
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "512M";
          content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; };
        };
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };
  };
}
```

```nix
# machines/nixos/vps/default.nix — minimal VPS base config
{ vars, ... }: {
  imports = [ ./disko.nix ./netbird-server.nix ];

  networking.hostName = "vps";

  # UEFI via systemd-boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # sops: VPS decrypts with its own SSH host key
  sops = {
    defaultSopsFile = ../../../secrets/vps.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  # Firewall: NetBird control plane ports + restricted SSH
  networking.firewall = {
    allowedTCPPorts = [ 80 443 ];
    allowedUDPPorts = [ 3478 ];
    allowedUDPPortRanges = [{ from = 49152; to = 65535; }];
  };

  # ACME/Let's Encrypt for netbird.grab-lab.gg
  security.acme = {
    acceptTerms = true;
    defaults.email = vars.adminEmail;
  };

  system.stateVersion = "25.11";
}
```

**Source:** nixos-anywhere README (github:nix-community/nixos-anywhere) ✅. disko ext4 from Pattern 4 ✅. `allowedUDPPortRanges` verified in NixOS options ✅.

---

## Pattern 14: NetBird client with sops-nix setup key and self-hosted management URL

The NixOS `services.netbird.clients.<name>` module (PR #354032) creates a per-client systemd service. The management URL for a self-hosted control plane must be set — the module provides `login.managementUrl` but **⚠️ VERIFY** whether it persists the URL correctly across restarts in your nixpkgs version. The manual fallback is documented below.

```nix
# homelab/netbird/default.nix
{ config, lib, vars, ... }:

let
  cfg = config.my.services.netbird;
in {
  options.my.services.netbird.enable = lib.mkEnableOption "NetBird VPN client";

  config = lib.mkIf cfg.enable {
    sops.secrets.netbird-setup-key = {
      sopsFile = ../../secrets/secrets.yaml;
      # No owner needed — service reads directly
    };

    # systemd-resolved must run for NetBird DNS, but with stub disabled for Pi-hole
    # (see Pattern 15)
    services.resolved = {
      enable = true;
      extraConfig = "DNSStubListener=no";
    };

    services.netbird.clients.wt0 = {
      port        = 51820;
      openFirewall         = true;
      openInternalFirewall = true;
      ui.enable   = false;

      login = {
        enable       = true;
        setupKeyFile = config.sops.secrets.netbird-setup-key.path;
        # ⚠️ VERIFY: managementUrl option may exist; if not, run manual step below
        # managementUrl = "https://netbird.${vars.domain}";
      };
    };

    # Enable IP forwarding — prerequisite for route advertisement
    services.netbird.useRoutingFeatures = "both";

    # Forward VPN traffic to LAN
    networking.firewall.extraCommands = ''
      iptables -A FORWARD -i wt0 -j ACCEPT
      iptables -A FORWARD -o wt0 -j ACCEPT
    '';
  };
}
```

**One-time management URL setup** (if `managementUrl` option is not available):
```bash
netbird-wt0 up \
  --management-url https://netbird.grab-lab.gg \
  --setup-key $(cat /run/secrets/netbird-setup-key)
```

Route advertisement (192.168.10.0/24) and DNS nameserver groups are configured **in the NetBird Dashboard**, not in NixOS. See `docs/NETBIRD-SELFHOSTED.md` for the step-by-step dashboard configuration.

**Source:** NixOS `services.netbird.clients` module options from nixpkgs PR #354032. `useRoutingFeatures` verified in nixpkgs option search ✅. `openInternalFirewall` ⚠️ VERIFY option name exists.

---

## Pattern 15: systemd-resolved with DNSStubListener=no (NetBird + Pi-hole coexistence)

NetBird requires `systemd-resolved` for its DNS route management — it calls `resolvectl` to register match-domain nameservers (e.g., `grab-lab.gg → Pi-hole overlay IP`). Pi-hole needs port 53. Both can coexist by disabling only the stub listener, which frees port 53 while keeping the resolved daemon running.

```nix
# In the machine config or homelab/netbird/default.nix
{
  # Pi-hole handles all DNS on port 53.
  # systemd-resolved runs as a routing daemon only — stub listener disabled.
  services.resolved = {
    enable = true;
    extraConfig = ''
      DNSStubListener=no
    '';
  };

  # Pi-hole is still responsible for /etc/resolv.conf via networking.nameservers
  # NixOS sets resolv.conf to Pi-hole's IP when DNSStubListener=no and
  # networking.nameservers is set.
  # networking.nameservers = [ "127.0.0.1" ];  # set in pebble/default.nix after Stage 3
}
```

**How it works:** With `DNSStubListener=no`, resolved does not bind `127.0.0.53:53`. Pi-hole claims port 53 on the host IP. NetBird's `resolvectl dns wt0 <pi-hole-overlay-ip>` and `resolvectl domain wt0 ~grab-lab.gg` calls succeed because resolved is still running — it just isn't serving queries itself.

**Alternative (unverified):** Set `NB_DNS_RESOLVER_ADDRESS` in the NetBird environment to move its internal resolver off port 53. Has had bugs in past versions (GitHub #2529) — the `DNSStubListener=no` approach is more reliable. ⚠️ VERIFY reliability in v0.68.x if you prefer this path.

**Source:** `services.resolved.extraConfig` verified in NixOS options ✅. `DNSStubListener=no` is a standard systemd-resolved config option ✅. Community reports confirm coexistence works with this approach.

---

## Pattern 16: systemd restart and ordering dependencies for homelab services

Three recurring situations require explicit systemd dependencies in this homelab. Apply them mechanically using the decision table below.

---

### A — OCI containers with published ports (Netavark DNAT flush)

**Problem:** When `nixos-rebuild switch` changes any `networking.firewall.*` option, NixOS
reloads `firewall.service`, which flushes and rewrites all iptables chains — including
`NETAVARK_INPUT` and `NETAVARK_FORWARD` that Podman/Netavark wrote for port DNAT. If the
container is not restarted after the flush, its published ports become unreachable from the
network even though the container is still running. The symptom is a timeout (not a
connection refused), because the iptables DNAT rule is simply gone.

**Rule:** Any OCI container using Podman's default bridge network with `ports = [...]`
needs `partOf`/`after firewall.service`. Containers using `--network=host` publish no
ports via Netavark and are not affected.

```nix
# In the service module (e.g. homelab/pihole/default.nix)
systemd.services.podman-<name> = {
  after  = [ "firewall.service" ];  # start after rules are written
  partOf = [ "firewall.service" ];  # restart whenever firewall restarts
};
```

**Applies to these homelab containers:**

| Container | Network mode | Needs fix? |
|-----------|-------------|------------|
| pihole | bridge (`ports = [...]`) | ✅ Yes — implemented |
| homeassistant | `--network=host` | ❌ No |
| esphome | `--network=host` | ❌ No |
| matter-server | `--network=host` | ❌ No |

---

### B — Services that read sops secrets via EnvironmentFile

**Problem:** sops-nix decrypts secrets during the NixOS activation script (before services
start). If a secret value changes in a subsequent deploy, the activation re-decrypts the
file, but the running service still has the old value in its environment. Without
`restartUnits`, the service is never told to reload.

**Rule:** Any service that reads a secret via `serviceConfig.EnvironmentFile` (not via a
config file the service re-reads on SIGHUP) needs `restartUnits` on its sops secret
declaration so sops-nix triggers a service restart after re-decryption.

```nix
sops.secrets."service/env" = {
  owner        = config.services.<name>.user;  # if the service runs as non-root
  restartUnits = [ "<name>.service" ];         # restart after secret changes
};
```

**Apply to:**

| Secret | Service | restartUnits needed? |
|--------|---------|----------------------|
| `caddy/env` (CLOUDFLARE_API_TOKEN) | `caddy.service` | ✅ implemented |
| `pihole/env` (web password) | `podman-pihole.service` | ⚠ not yet — low priority (password changes are rare) |
| `grafana_admin_password` | `grafana.service` | ⚠ add in Stage 5 |
| `netbird-setup-key` | `systemd-netbird-wt0.service` | ⚠ add in Stage 6b |

Note: Grafana injects its admin password via `$__file{/run/secrets/...}` syntax in
`settings.security.admin_password`, not via EnvironmentFile — but it still needs a restart
to pick up a changed secret because Grafana reads the file at startup, not on every request.

---

### C — Service start ordering across dependent services

**Problem:** Some services fail or produce errors at startup if their dependencies aren't
ready yet. `After` establishes ordering without creating a hard dependency; `Requires`
(or `wants` for a soft dependency) additionally ensures the dependency is started.

**Rule:** Use `after` + `wants` (soft: best-effort) when the dependent service retries
connections on its own. Use `after` + `requires` (hard) only when the service will crash
without the dependency.

```nix
# Home Assistant — MQTT broker should be up before HA tries to connect
systemd.services.podman-homeassistant = {
  after = [ "mosquitto.service" ];
  wants = [ "mosquitto.service" ];  # soft: HA retries MQTT connections anyway
};

# ESPHome and Matter Server — mDNS requires Avahi to be running
systemd.services.podman-esphome = {
  after = [ "avahi-daemon.service" ];
  wants = [ "avahi-daemon.service" ];
};

systemd.services.podman-matter-server = {
  after = [ "avahi-daemon.service" ];
  wants = [ "avahi-daemon.service" ];
};

# Promtail — log shipper should start after Loki is ready to receive
systemd.services.promtail = {
  after = [ "loki.service" ];
  wants = [ "loki.service" ];
};
```

**Full dependency picture for this homelab:**

```
firewall.service
    └─ partOf ─▶ podman-pihole.service
                     └─ (Pi-hole DNS used by Caddy, NetBird, pebble system)

mosquitto.service
    └─ wants/after ─▶ podman-homeassistant.service

avahi-daemon.service
    ├─ wants/after ─▶ podman-esphome.service
    └─ wants/after ─▶ podman-matter-server.service

loki.service
    └─ wants/after ─▶ promtail.service
```

Native services (Prometheus, Grafana, Loki, Uptime Kuma, Homepage, Mosquitto, Wyoming
pipeline) need no special ordering beyond what systemd's default `After=network.target`
provides — they all bind to localhost and retry connections internally.

**Source:** Discovered via live debugging (Netavark flush). `partOf` and `wants` semantics
from systemd man pages. `restartUnits` from sops-nix README ✅.

---

## Pattern 17: Podman volume directories — own by container UID, not root

**Problem:** `systemd.tmpfiles.rules` with type `d` defaults to `root root` ownership.
Rootful Podman shares the host UID namespace — no remapping. If the containerised process
drops privileges after startup (e.g., Pi-hole's FTL binds port 53 as root, then drops to
UID 1000), it can no longer create files in the host-owned directory. SQLite WAL mode
needs to create `<db>-wal` and `<db>-shm` alongside the database file; if the directory
is not writable by the running UID, every write fails with:

```
attempt to write a readonly database
```

The database *file* itself may be owned correctly (`1000:1000 rw-rw----`) and still be
unwritable — because SQLite's WAL lock files must be created in the same directory, and
directory write permission is what's missing.

**Fix:** set the `d` rule owner to the UID the container process actually runs as. For
Pi-hole v6, that is UID/GID 1000 (`pihole` user inside the container).

```nix
systemd.tmpfiles.rules = [
  # UID 1000 = pihole user inside the container (rootful Podman, no UID remapping).
  # SQLite WAL mode requires directory write access to create .db-wal/.db-shm files.
  "d /var/lib/pihole 0755 1000 1000 -"
];
```

**Immediate fix for an already-created directory** (tmpfiles `d` only adjusts ownership
if it created the directory; an existing `root:root` directory must be fixed manually):

```bash
sudo chown 1000:1000 /var/lib/pihole
# No container restart needed — directory permissions take effect immediately.
```

**Checklist when adding a new Podman volume:**
1. Find out what UID the container process runs as after startup (`podman exec <name> ps aux`).
2. If it drops to a non-root UID, set that UID in the `d` tmpfiles rule.
3. If the directory already exists on the host, run `sudo chown UID:GID /var/lib/<service>`.
4. Containers using `--network=host` or that stay as root throughout are unaffected.

**Source:** Diagnosed live on Pi-hole v6 (pihole/pihole:2025.02.1). SQLite WAL behaviour
confirmed in SQLite documentation — the directory containing the database must be writable
for WAL lock file creation ✅.

---

## Pattern 18: Always use IP addresses for SSH, never domain names

**Problem:** When deploying to multiple machines, DNS resolution can return the wrong IP
if Pi-hole or split-horizon DNS is misconfigured. A command like `ssh admin@netbird.grab-lab.gg`
may resolve to a LAN server (192.168.10.50) instead of the intended VPS (204.168.181.110),
causing the wrong machine to receive the deployment — potentially breaking the local server
with incompatible configuration.

**Rule:** Always use explicit IP addresses from `vars.nix` for SSH and deployment commands.
Never rely on domain names for infrastructure operations.

```nix
# machines/nixos/vars.nix — single source of truth for IPs
{
  serverIP = "192.168.10.50";   # pebble (homelab)
  vpsIP = "204.168.181.110";    # VPS (NetBird control plane)
  routerIP = "192.168.1.1";
}
```

```just
# justfile — use IPs, not domains
ssh-pebble:
    ssh admin@192.168.10.50

ssh-vps:
    ssh admin@204.168.181.110

deploy-vps:
    # deploy-rs uses hostname from flakeHelpers.nix — ensure it's the IP, not domain
    nix run github:serokell/deploy-rs -- -s .#vps
```

```nix
# flakeHelpers.nix — deploy.nodes hostname must be IP for VPS
deploy.nodes.${hostname} = {
  hostname = deployHostname hostname;  # Returns IP from vars.nix, not domain
  # ...
};
```

**Recovery if wrong machine was deployed:**
1. Physical access: reboot, select previous NixOS generation from GRUB menu
2. Boot into working generation
3. Run `sudo /run/current-system/bin/switch-to-configuration boot` to make it default

**Source:** Discovered during Stage 7a when `ssh admin@netbird.grab-lab.gg` resolved to
pebble (192.168.10.50) instead of VPS, deploying VPS config to the homelab server and
breaking SSH access. Required physical console recovery ✅.
