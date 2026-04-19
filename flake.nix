{
  description = "Homelab NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Used only for the netbird package overlay — 25.11 is stuck on 0.60.2
    # which is protocol-incompatible with the 0.68.x management server.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

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
      # Homelab server: ZFS, all services, Podman containers
      (mkNixos "pebble" inputs.nixpkgs [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./homelab
        ./modules/networking
        ./modules/podman
      ])

      # VPS control plane: NetBird server only, no homelab services
      (mkNixos "vps" inputs.nixpkgs [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
      ])

      {
        checks = builtins.mapAttrs
          (system: deployLib: deployLib.deployChecks self.deploy)
          deploy-rs.lib;
      }

      {
        devShells.x86_64-linux.default =
          nixpkgs.legacyPackages.x86_64-linux.mkShell {
            packages = with nixpkgs.legacyPackages.x86_64-linux; [
              pre-commit
              gitleaks
            ];
            shellHook = "pre-commit install";
          };
      }
    ];
}
