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
    fmapSystems =
      f: nixpkgs.lib.genAttrs (import systems) (system: f { pkgs = import nixpkgs { inherit system; }; });
  in
  {
    devShells = fmapSystems (
      { pkgs }:
      {
        default =
        let
          python = pkgs.python312;
        in
        pkgs.mkShellNoCC {
          packages = with pkgs; [
            hello
            (python.withPackages (ps: with ps;
            [
              jwcrypto
            ]))
          ];
        };
      }
    );
  };
}
