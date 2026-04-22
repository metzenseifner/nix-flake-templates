{
  description = "Minimal Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hofs = {
      url = "github:metzenseifner/nix-derivation-hofs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, ... }:
    let
      # Functor: a functor because it maps a package-producing function across a pre-defined set of architectural contexts, preserving structure of output
      # Maps a "System" category to a "Derivation/Package" category.
      traverseSystems =
        f:
        inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed (
          system: f inputs.nixpkgs.legacyPackages.${system}
        );
      perSystemOutputs =
        system: pkgs:
        let
          scripts = rec {
            help = pkgs.writeShellScriptBin "my-help" ''

            '';
            default = help;
          };
          mkBinApp = drv: bin: {
            type = "app";
            program = "${drv}/bin/${bin}";
          };
        in
        # Define outputs based on a per system, per pkgs basis
        {
          packages = scripts;
          apps = {
            help = mkBinApp scripts.help "my-help";
          };
          devShells.default = pkgs.mkShell {
            packages = [
              scripts.help
            ];
          };
        };
    in
    {
      # Projections over Record(system)
      packages = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).packages);
      apps = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).apps);
      # devShells = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).devShells);
      # checks = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).checks);
    };
}
