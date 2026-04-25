---
kind: pattern
number: 2
tags: [flake, helpers, DRY]
---

# Pattern 2: flakeHelpers.nix — DRY machine definitions

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
