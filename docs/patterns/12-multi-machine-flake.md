---
kind: pattern
number: 12
tags: [flake, deploy-rs, multi-machine]
---

# Pattern 12: Multi-machine flake with deploy-rs (homelab + VPS)

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
