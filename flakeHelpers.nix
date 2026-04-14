inputs:
let
  vars = import ./machines/nixos/vars.nix;

  # Resolve deploy hostname: always use IPs, never domains (Pattern 18)
  # Domain resolution can hit split-horizon DNS and deploy to wrong machine.
  deployHostname = hostname:
    if hostname == "pebble" then vars.serverIP
    else if hostname == "vps" then vars.vpsIP
    else hostname;

  mkNixos = hostname: nixpkgsVersion: extraModules: {
    deploy.nodes.${hostname} = {
      hostname = deployHostname hostname;
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
