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

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      disko,
      sops-nix,
      ...
    }@inputs:
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

      # Media/productivity server: Immich, Jellyfin, Paperless, etc.
      (mkNixos "boulder" inputs.nixpkgs [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./homelab
        ./modules/networking
        ./modules/podman
      ])

      # VPS: WireGuard hub + log shipping to pebble Loki
      (mkNixos "vps" inputs.nixpkgs [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./homelab/alloy # Stage 10 — log shipping to pebble Loki
      ])

      {
        checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
      }

      {
        # Standalone docs-site package for local preview and CI builds
        packages.x86_64-linux.docs-site = nixpkgs.legacyPackages.x86_64-linux.stdenv.mkDerivation {
          name = "homelab-docs-site";
          src = ./.;

          nativeBuildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
            python311
            python311Packages.mkdocs
            python311Packages.mkdocs-material
            python311Packages.pymdown-extensions
          ];

          buildPhase = ''
            export HOME=$(mktemp -d)
            mkdocs build --strict --site-dir $out
          '';

          installPhase = ''
            # Output is already in $out from buildPhase
            echo "Site built to $out"
          '';
        };

        formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;

        devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
          packages = with nixpkgs.legacyPackages.x86_64-linux; [
            pre-commit
            gitleaks
            nixfmt-rfc-style
          ];
          shellHook = "pre-commit install";
        };

        devShells.x86_64-linux.mcp = nixpkgs.legacyPackages.x86_64-linux.mkShell {
          packages = with nixpkgs.legacyPackages.x86_64-linux; [
            python311
            python311Packages.pip
            python311Packages.pytest
            python311Packages.pytest-asyncio
          ];
          shellHook = ''
            cd .agent/mcp
            pip install -e ".[dev]" --quiet
          '';
        };
      }
    ];
}
