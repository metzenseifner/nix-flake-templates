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
      # Map over systems and create attrset whose keys are systems and values
      # are produced by a HOF lambda that takes a 1-tuple system and evaluates
      # to any value. e.g.
      # intermediate result: { x86_64-linux = f "x86_64-linux" pkgsForThat; aarch64-darwin = f "aarch64-darwin" pkgsForThat; … }
      fmapSystems =
        f:
        inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed (
          system: f system inputs.nixpkgs.legacyPackages.${system} # changed: pass system too
        );

      perSystemOutputs =
        system: pkgs:
        let
          inherit (nix-derivation-hofs.lib) withHelps mkHelpPkg; # changed: withDocs was renamed
          scriptFactories = {
            a =
              name:
              withHelps "Usage: a" (
                pkgs.writeShellScriptBin name ''
                  set -euo pipefail
                  ${pkgs.curl}/bin/curl -s "https://example.com/api" | ${pkgs.jq}/bin/jq '.data'
                ''
              );
            b =
              name:
              withHelps "Usage: b" (
                pkgs.writeShellApplication {
                  inherit name;
                  runtimeInputs = [
                    pkgs.curl
                    pkgs.jq
                  ];
                  text = ''
                    curl -s "https://example.com/api" | jq '.data'
                  '';
                }
              );
          };
          resolved = pkgs.lib.mapAttrs (name: f: f name) scriptFactories;
          scripts = resolved // {
            help = mkHelpPkg {
              inherit pkgs;
              name = "help";
              derivations = builtins.attrValues resolved;
            };
            default = resolved.a;
          };
        in
        {
          packages = scripts;
          apps =
            let
              mkBinApp = drv: bin: {
                type = "app";
                program = "${drv}/bin/${bin}";
                meta.description = drv.__doc or bin; # changed: silences flake check warning
              };
            in
            pkgs.lib.mapAttrs (name: drv: mkBinApp drv name) (
              pkgs.lib.filterAttrs (name: _: name != "default") scripts
            );
          devShells.default = pkgs.mkShell {
            packages = builtins.attrValues resolved ++ [ scripts.help ]; # changed: scripts on search path
          };
        };

      # This is the System↔Output transpose: perSystem is keyed by system,
      # the flake schema wants each field keyed by system.
      # Compute each system's outputs once, then project each field out.
      perSystem = fmapSystems perSystemOutputs;
      project = field: builtins.mapAttrs (_: out: out.${field}) perSystem;
    in
    {
      # Projections over Record(system)
      packages = project "packages";
      apps = project "apps";
      devShells = project "devShells";
      # checks = project "checks";
    };
}
