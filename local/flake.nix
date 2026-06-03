{
  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
  {
    self,
    nixpkgs,
    systems,
  }:
  let
    # Functor: Maps a "System" category to a "Derivation/Package" category.
    fmapSystems =
      f: nixpkgs.lib.genAttrs (import systems) (system: f { pkgs = import nixpkgs { inherit system; }; });
  in
  {
    devShells = fmapSystems (
      { pkgs }:
      {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            (callPackage ./default.nix {})
          ];
        };
      }
    );
  };
}
