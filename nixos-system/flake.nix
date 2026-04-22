{
  description = "Minimal NixOS system configuration for any architecture";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, systems, disko, ... }:
    let
      # Helper to generate configurations for each system
      traverseSystems = f: nixpkgs.lib.genAttrs (import systems) (system: f system);
    in
    {
      # NixOS configurations for different architectures
      nixosConfigurations = {
        # x86_64 Linux system
        nixos-x86_64 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./configuration.nix
            # Uncomment to use disko for automated partitioning:
            # disko.nixosModules.disko
            # ./disk-config.nix
          ];
        };

        # aarch64 Linux system (ARM64)
        nixos-aarch64 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            ./configuration.nix
            # Uncomment to use disko for automated partitioning:
            # disko.nixosModules.disko
            # ./disk-config.nix
          ];
        };
      };

      # Example: build images for different architectures
      packages = traverseSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          # Add custom packages here if needed
        }
      );
    };
}
