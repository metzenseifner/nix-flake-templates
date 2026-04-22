{
  description = "Minimal Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-derivation-hofs = {
      url = "github:metzenseifner/nix-derivation-hofs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, nix-derivation-hofs, ... }:
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
          inherit (nix-derivation-hofs.lib) withDocs mkHelpPkg;
          scripts = rec {
            a = withDocs "Usage: a" (name:
              pkgs.pkgs.writeShellScriptBin name ''
                # Nix overwrites the shebang with a default shell - injects the bash shebang, nothing else. You're on your own for error handling.
                set -euo pipefail
                # hermetically sealed dependencies (only ref the Nix Store) - from alchemist Hermes Trismegistus, meaning airtight
                ${pkgs.curl}/bin/curl -s "https://example.com/api" | ${pkgs.jq}/bin/jq '.data'
              ''
            );
            b = withDocs "Usage: b" (name:
              pkgs.writeShellApplication {
                # injects set -euo pipefail automatically, plus runs shellcheck on your script at build time. The most opinionated/safe option.
                name = name;
                # hermetically sealed dependencies (only ref the Nix Store) - from alchemist Hermes Trismegistus, meaning airtight
                runtimeInputs = [
                  pkgs.curl
                  pkgs.jq
                ];
                text = ''
                  curl -s "https://example.com/api" | jq '.data'
                '';
              }
            );
            help = mkHelpPkg {
              inherit pkgs;
              name = "help";
              derivations = scripts;
            };
            default = a;
          };
        in
        # Define outputs based on a per system, per pkgs basis
        {
          packages = scripts;
          apps =
            let
              mkBinApp = drv: bin: {
                type = "app";
                program = "${drv}/bin/${bin}";
              };
            in
            pkgs.lib.mapAttrs (name: drv: mkBinApp drv name) (
              pkgs.lib.filterAttrs (name: _: name != "default") scripts
            );
          #apps = {
          #  help = mkBinApp scripts.help "my-help";
          #};
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
