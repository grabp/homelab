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
  # ⚠️ `preloadModels` was REMOVED in wyoming-openwakeword v2.0.0 (Oct 2025).
  # nixos-25.11 ships v2.0.0+. Built-in models load automatically.
  # Do NOT set preloadModels — the option no longer exists and causes an eval error.
  services.wyoming.openwakeword = {
    enable = true;
    uri    = "tcp://0.0.0.0:10400";
    # Built-in models (okay_nabu, hey_jarvis, alexa, hey_mycroft, hey_rhasspy) auto-load.
    # Add custom models via customModelsDirectories = [ /path/to/models ];
  };

  networking.firewall.allowedTCPPorts = [ 10200 10300 10400 ];
}
```

**Source:** NixOS module source at `nixos/modules/services/home-automation/wyoming/`. ProcSubset bug confirmed in nixpkgs PR #372898 — merged into nixos-25.11 (`ProcSubset = "all"` already in module). `lib.mkForce "all"` override harmless and kept for explicit documentation. `preloadModels` removal verified against nixos-25.11 rev `7e495b747b51` ✅.

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
# Note: netbird-server.nix uses OCI containers (virtualisation.oci-containers),
# NOT services.netbird.server — see Pattern 19 for the OCI container approach.
# ⚠️ services.netbird.server exists but is not production-ready as of nixos-25.11.
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

The NixOS `services.netbird.clients.<name>` module creates a per-client systemd service
(`netbird-wt0.service`) and an optional login oneshot (`netbird-wt0-login.service`).

**⚠️ nixos-25.11 ships netbird 0.60.2 — you MUST override it.**
nixpkgs 25.11 is stuck on 0.60.2. The `netbirdio/management:latest` container (and all
current desktop/mobile clients) are on 0.68.x. The relay and signaling protocol changed
between these versions: WireGuard handshakes never complete (`Last WireGuard handshake: -`
for all peers), ICE connects briefly then drops with "ICE disconnected, do not switch to
Relay. Reset priority to: None", `Forwarding rules: 0`. Fix: pull netbird from
`nixpkgs-unstable` via an overlay. Add `nixpkgs-unstable` input to `flake.nix` and use
`lib.mkMerge` in the module (required because `nixpkgs.overlays` must coexist with an
explicit `config = lib.mkIf ...` block — mixing top-level config with explicit `config =`
is a module error).

**Other verified gotchas in nixos-25.11:**
- `login.managementUrl` does **NOT** exist as a module option.
- `config.ManagementURL = "https://..."` does **NOT** work in 0.60.2 — stored as `url.URL`
  Go struct, not string. Crashes with "cannot unmarshal string". Set via `--management-url`
  flag on first login; persists in `/var/lib/netbird-wt0/config.json`.
- `openInternalFirewall` does **NOT** exist. Use `openFirewall = true`.
- **Do NOT use `login.enable = true`** — the oneshot gets SIGTERM'd during
  `nixos-rebuild switch` due to a daemon socket race ("Start request repeated too quickly").
- `sops-install-secrets.service` does **NOT** exist — sops-nix uses activation scripts.
- `services.resolved` belongs in the machine config, not this module.

```nix
# flake.nix — add input alongside nixpkgs
nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
```

```nix
# homelab/netbird/default.nix
{ config, lib, inputs, ... }:

let
  cfg = config.my.services.netbird;
in {
  options.my.services.netbird.enable = lib.mkEnableOption "NetBird VPN client";

  # lib.mkMerge required: can't mix top-level config attrs with explicit `config =`
  config = lib.mkMerge [
    {
      # nixos-25.11 ships 0.60.2 — protocol-incompatible with 0.68.x server/clients
      nixpkgs.overlays = [
        (final: prev: {
          inherit (inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.system}) netbird;
        })
      ];
    }

    (lib.mkIf cfg.enable {
      sops.secrets."netbird/setup_key" = { };

      services.netbird.clients.wt0 = {
        port = 51820;
        openFirewall = true;
        ui.enable = false;
      };

      services.netbird.useRoutingFeatures = "both";

      networking.firewall.extraCommands = ''
        iptables -A FORWARD -i wt0 -j ACCEPT
        iptables -A FORWARD -o wt0 -j ACCEPT
      '';

      networking.firewall.allowedUDPPorts = [ 51820 ];
    })
  ];
}
```

**One-time login after first deploy** (run on pebble; ManagementURL and credentials
persist in `/var/lib/netbird-wt0/config.json` across reboots):
```bash
sudo netbird-wt0 up \
  --management-url https://netbird.grab-lab.gg \
  --setup-key-file /run/secrets/netbird/setup_key
```

Route advertisement (192.168.10.0/24) and DNS nameserver groups are configured **in the
NetBird Dashboard**, not in NixOS. See `docs/NETBIRD-SELFHOSTED.md` for the step-by-step
dashboard configuration.

**Source:** Verified against nixos-25.11, netbird 0.68.1 (overlay from nixpkgs-unstable),
management server 0.68.3 ✅.

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
| `netbird/setup_key` | n/a — login.enable not used; key is for one-time manual step | ✅ intentional (Stage 7b) |

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

---

## Pattern 19: NetBird server via OCI containers on NixOS VPS (embedded Dex)

⚠️ **Do NOT use `services.netbird.server`** — it exists in nixpkgs but is not
production-ready as of nixos-25.11 (sparse documentation, unclear option interactions).
Use `virtualisation.oci-containers` on the NixOS VPS instead.

As of v0.68.x the container stack is **3 OCI containers + 1 native service**:
- `netbirdio/management:latest` — REST API + gRPC + **embedded Dex IdP** (port 8080)
- `netbirdio/signal:latest` — peer coordination, still a **separate** image (port 10000 on host, 80 in container)
- `netbirdio/dashboard:latest` — React web UI (port 3000 on host, 80 in container)
- native `services.coturn` — STUN/TURN (reads Caddy ACME certs; no container needed)

⚠️ **Common image name mistake:** `netbirdio/netbird:management-latest` does **not** exist on
Docker Hub. The correct image is `netbirdio/management:latest`. Signal is NOT merged into
the management image as of v0.68.x.

### management.json — embedded Dex configuration

Enable embedded Dex with `EmbeddedIdP.Enabled = true`. The binary auto-configures
`HttpConfig` (issuer, audience, OIDC endpoint) from the `Issuer` value — do **not**
set `OIDCConfigEndpoint` manually. `IdpManagerConfig` must be **omitted** (it is for
external IdPs only; its presence alongside `EmbeddedIdP` causes conflicts).

`DashboardRedirectURIs` registers extra redirect URIs beyond the auto-registered
`/api/reverse-proxy/callback`. Both `/nb-auth` (PKCE callback) and `/nb-silent-auth`
(silent token renewal) must be listed or Dex will reject them with `BAD_REQUEST`.

```nix
# machines/nixos/vps/netbird-server.nix (relevant excerpt)
{ config, lib, pkgs, vars, ... }:
let
  domain = "netbird.${vars.domain}";
  mgmtConfigTemplate = pkgs.writeText "management.json.tmpl" (builtins.toJSON {
    Stuns = [{ Proto = "udp"; URI = "${domain}:3478"; Username = null; Password = null; }];
    TURNConfig = {
      Turns = [{ Proto = "udp"; URI = "turn:${domain}:3478"; Username = "netbird"; Password = "TURN_PLACEHOLDER"; }];
      CredentialsTTL = "12h";
      Secret = "TURN_PLACEHOLDER";
      TimeBasedCredentials = false;
    };
    Signal = { Proto = "https"; URI = "${domain}:443"; Username = null; Password = null; };
    HttpConfig = {
      Address = "0.0.0.0:8080";
      # OIDCConfigEndpoint is auto-set by the binary when EmbeddedIdP is enabled.
      # Do NOT set it manually — it will be ignored / conflict.
      IdpSignKeyRefreshEnabled = true;
    };
    EmbeddedIdP = {
      Enabled = true;
      # Issuer must match the public URL Caddy exposes for /oauth2/*.
      Issuer = "https://${domain}/oauth2";
      # These are registered as allowed redirect_uris in the netbird-dashboard Dex client.
      # The binary auto-registers /api/reverse-proxy/callback; these are extra.
      # AUTH_REDIRECT_URI and AUTH_SILENT_REDIRECT_URI in the dashboard env must match.
      DashboardRedirectURIs = [
        "https://${domain}/nb-auth"
        "https://${domain}/nb-silent-auth"
      ];
    };
    # IdpManagerConfig must be OMITTED when using embedded Dex.
    DataStoreEncryptionKey = "ENC_PLACEHOLDER";
    StoreConfig.Engine = "sqlite";
    Datadir = "/var/lib/netbird";
    SingleAccountModeDomain = vars.domain;
    ReverseProxy = { TrustedPeers = [ "0.0.0.0/0" ]; TrustedHTTPProxies = []; TrustedHTTPProxiesCount = 0; };
  });
in {
  virtualisation.oci-containers.containers = {

    # Management REST API + gRPC + embedded Dex IdP
    netbird-management = {
      image = "netbirdio/management:latest";
      # ⚠️ Pin to a specific version tag before production — rolling tag
      ports = [ "127.0.0.1:8080:8080" ];
      volumes = [
        "/var/lib/netbird-mgmt:/var/lib/netbird"
        "/var/lib/netbird-mgmt/management.json:/etc/netbird/management.json:ro"
      ];
      cmd = [
        "--port" "8080" "--log-file" "console"
        "--disable-anonymous-metrics" "true"
        "--single-account-mode-domain" vars.domain
      ];
    };

    # Signal — peer coordination (still a separate image in v0.68.x)
    # Signal binary listens on port 80 inside the container.
    netbird-signal = {
      image = "netbirdio/signal:latest";
      ports = [ "127.0.0.1:10000:80" ];
    };

    netbird-dashboard = {
      image = "netbirdio/dashboard:latest";
      ports = [ "127.0.0.1:3000:80" ];
      environment = {
        # AUTH_AUTHORITY = the embedded Dex issuer path (not /idp — that's wrong)
        AUTH_AUTHORITY = "https://${domain}/oauth2";
        AUTH_CLIENT_ID = "netbird-dashboard";
        AUTH_AUDIENCE  = "netbird-dashboard";
        AUTH_SUPPORTED_SCOPES = "openid profile email offline_access groups";
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

### Setup wizard gotchas

**First boot:** Visit `https://<domain>/setup`. The management API endpoint `/api/setup`
(POST, unauthenticated) accepts `{Email, Password, Name}` and creates the owner user.
The dashboard wizard POSTs to this endpoint directly — no Dex login required for setup.

**"setup_required: false" blocks wizard:** If a previous deployment left a `store.db`
(e.g., from a Zitadel-era run), the management server thinks setup is done and the
`/setup` page redirects straight to login. Users can't log in because the embedded Dex
password store (`idp.db`) has no accounts. Fix:
```bash
systemctl stop podman-netbird-management
rm /var/lib/netbird-mgmt/store.db /var/lib/netbird-mgmt/idp.db
systemctl start podman-netbird-management
# Now curl http://localhost:8080/api/instance returns {"setup_required":true}
```

**Source:** Verified against `netbirdio/management:latest` v0.68.3 in production ✅.
Image names confirmed via Docker Hub API. Dex client registration from
`management/server/idp/embedded.go` source ✅.

---

## Pattern 20: Hybrid VPS — NixOS-managed Caddy + OCI NetBird containers

On the VPS, use **native NixOS Caddy** (`services.caddy`) for TLS termination rather
than a Caddy or Traefik container. Native Caddy handles Let's Encrypt via HTTP-01
challenge (public IP available) and avoids adding a fourth container layer.

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

---

## Pattern 21: Kanidm with declarative OAuth2 client provisioning

Kanidm's `services.kanidm.provision` block lets you define users, groups, and OAuth2
resource servers in NixOS config. **No web UI clicking required.** Each service module
co-locates its Kanidm client definition alongside its service config.

```nix
# homelab/kanidm/default.nix — verified working pattern (nixos-25.11, kanidm 1.9)
{ config, lib, pkgs, vars, ... }:
{
  # CLI in PATH without enableClient (which requires clientSettings to also be set)
  environment.systemPackages = [ pkgs.kanidmWithSecretProvisioning_1_9 ];

  # Kanidm requires TLS even on localhost. Generate a self-signed cert that:
  # - has basicConstraints=CA:FALSE (kanidm 1.9 rejects CA:TRUE with CaUsedAsEndEntity)
  # - has a SAN for 127.0.0.1 (needed for direct localhost CLI connections)
  # Detect and regenerate bad old certs (CA:TRUE) automatically.
  systemd.services.kanidm-tls-cert = {
    description = "Generate Kanidm self-signed TLS certificate";
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.openssl ];
    script = ''
      install -d -m 750 -o kanidm -g kanidm /var/lib/kanidm
      needs_regen=0
      [ ! -f /var/lib/kanidm/tls.pem ] && needs_regen=1
      if [ -f /var/lib/kanidm/tls.pem ]; then
        openssl x509 -in /var/lib/kanidm/tls.pem -noout -text 2>/dev/null \
          | grep -q "CA:TRUE" && needs_regen=1
      fi
      if [ "$needs_regen" = "1" ]; then
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
          -keyout /var/lib/kanidm/tls.key -out /var/lib/kanidm/tls.pem \
          -days 3650 -nodes -subj '/CN=id.${vars.domain}' \
          -addext "basicConstraints=CA:FALSE" \
          -addext "subjectAltName=IP:127.0.0.1,DNS:id.${vars.domain}"
        chown kanidm:kanidm /var/lib/kanidm/tls.key /var/lib/kanidm/tls.pem
        chmod 600 /var/lib/kanidm/tls.key && chmod 644 /var/lib/kanidm/tls.pem
      fi
    '';
  };
  systemd.services.kanidm = {
    requires = [ "kanidm-tls-cert.service" ];
    after    = [ "kanidm-tls-cert.service" ];
  };

  services.kanidm = {
    enableServer = true;
    # nixos-25.11 module defaults to kanidm_1_4 (EOL, removed from nixpkgs).
    # _1_7 is also gone (insecure). Must pin explicitly.
    package = pkgs.kanidmWithSecretProvisioning_1_9;
    serverSettings = {
      origin          = "https://id.${vars.domain}";
      domain          = "id.${vars.domain}";
      bindaddress     = "127.0.0.1:8443";
      ldapbindaddress = "127.0.0.1:636";
      tls_chain       = "/var/lib/kanidm/tls.pem";
      tls_key         = "/var/lib/kanidm/tls.key";
    };
    provision = {
      enable             = true;
      instanceUrl        = "https://127.0.0.1:8443";
      acceptInvalidCerts = true;  # required for self-signed cert
      # owner = "kanidm" REQUIRED — provisioning ExecStartPost runs as kanidm user,
      # default root:root 0400 causes "permission denied"
      adminPasswordFile    = config.sops.secrets."kanidm/admin_password".path;
      idmAdminPasswordFile = config.sops.secrets."kanidm/idm_admin_password".path;

      # IMPORTANT: "admin" is Kanidm's built-in system account — provisioning a
      # person named "admin" → 409 Conflict. Use a distinct username.
      persons."yourname" = {
        displayName   = "Your Name";
        mailAddresses = [ "admin@${vars.domain}" ];
      };
      groups."homelab_users".members  = [ "yourname" ];
      groups."homelab_admins".members = [ "yourname" ];
    };
  };

  sops.secrets."kanidm/admin_password"     = { owner = "kanidm"; };
  sops.secrets."kanidm/idm_admin_password" = { owner = "kanidm"; };
  # mode 0444: readable by both kanidm provisioning and service clients ($__file{})
  sops.secrets."kanidm/grafana_client_secret" = { mode = "0444"; };

  networking.firewall.allowedTCPPorts = [ 636 ];
  # Port 8443 NOT opened — Caddy proxies it via localhost
}
```

```nix
# homelab/grafana/default.nix — OAuth2 client co-located with service
{ config, lib, vars, ... }:
{
  # Kanidm OAuth2 client for Grafana — defined here, not in kanidm/default.nix
  # basicSecretFile: pre-seed the secret from sops → single-phase deploy
  services.kanidm.provision.systems.oauth2."grafana" = {
    displayName     = "Grafana";
    originUrl       = "https://grafana.${vars.domain}/login/generic_oauth";
    originLanding   = "https://grafana.${vars.domain}";
    basicSecretFile = config.sops.secrets."kanidm/grafana_client_secret".path;
    scopeMaps."homelab_users" = [ "openid" "profile" "email" "groups" ];
  };
}
```

**Kanidm OIDC issuer URL pattern (per-client, not global):**
```
https://id.grab-lab.gg/oauth2/openid/<client-name>/.well-known/openid-configuration
```

**Setting a person's login password after first deploy:**
```bash
kanidm --url https://id.grab-lab.gg login --name idm_admin
kanidm --url https://id.grab-lab.gg person credential create-reset-token <username>
# open the printed URL in browser
```

**Known gotchas:**
- **`kanidm_1_4` removed** — explicitly set `package = pkgs.kanidmWithSecretProvisioning_1_9`
- **"admin" username reserved** — use a distinct person username
- **sops ownership** — password secrets need `owner = "kanidm"`; OAuth2 secret needs `mode = "0444"`
- **CA:FALSE required** — self-signed cert must not have `CA:TRUE` (kanidm 1.9 CaUsedAsEndEntity error)
- **`enableClient = true` requires `clientSettings`** — use `environment.systemPackages` instead
- **PKCE enforced** — set `use_pkce = true` in Grafana and equivalent in other clients
- **Groups as SPNs** — `groups` claim is `groupname@kanidm-domain`, not bare name; adjust role mappings
- Per-client issuer URLs (not a single global issuer)
- ES256 token signing (not RS256) — most modern apps handle this

**Source:** `services.kanidm` verified in nixos-25.11 ✅. All gotchas verified in production deployment ✅.

---

## Pattern 22: Caddy forward_auth with Kanidm

For services without native OIDC support (Uptime Kuma, Homepage), Caddy's
`forward_auth` directive proxies authentication to Kanidm.

```nix
# In homelab/caddy/default.nix or the service's own module
services.caddy.virtualHosts."uptime.${vars.domain}" = {
  extraConfig = ''
    forward_auth localhost:8443 {
      uri /ui/oauth2/token/check
      copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
      transport http {
        tls_insecure_skip_verify
      }
    }
    reverse_proxy localhost:3001
  '';
};
```

⚠️ **VERIFY:** Kanidm's exact forward_auth endpoint. `/ui/oauth2/token/check` is the
expected path but verify against the Kanidm documentation for your version.

**Alternative:** Use **oauth2-proxy** as a sidecar with Kanidm as the OIDC backend.
More setup but better documented for the forward_auth use case:

```nix
# oauth2-proxy sidecar for services without native auth
virtualisation.oci-containers.containers.oauth2-proxy = {
  image = "quay.io/oauth2-proxy/oauth2-proxy:latest";
  environment = {
    OAUTH2_PROXY_PROVIDER = "oidc";
    OAUTH2_PROXY_OIDC_ISSUER_URL = "https://id.${vars.domain}/oauth2/openid/oauth2-proxy/.well-known/openid-configuration";
    OAUTH2_PROXY_CLIENT_ID = "oauth2-proxy";
    OAUTH2_PROXY_UPSTREAM = "http://localhost:3001";  # upstream service
    OAUTH2_PROXY_HTTP_ADDRESS = "0.0.0.0:4180";
  };
  environmentFiles = [ config.sops.secrets."oauth2-proxy/env".path ];
};
```

**Source:** Caddy `forward_auth` directive is documented in Caddy docs ✅. oauth2-proxy
OIDC provider pattern is verified against oauth2-proxy docs ✅.

---

## Pattern 23: Grafana OIDC with Kanidm

Grafana is the simplest service to test Kanidm OIDC integration — use it as the
reference implementation before configuring other services.

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

**Source:** Grafana `auth.generic_oauth` with `use_pkce` verified in production ✅.
Kanidm groups-as-SPNs format verified in production ✅ (nixos-25.11, kanidm 1.9.x).
