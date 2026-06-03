{
  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nur.url = "github:nix-community/NUR";
  };

  outputs =
  {
    self,
    nixpkgs,
    systems,
    nur,
  }:
  let
    fmapSystems =
      f:
      nixpkgs.lib.genAttrs (import systems) (
        system:
        f {
          pkgs = import nixpkgs {
            overlays = [ nur.overlay ];
            inherit system;
          };
        }
      );
  in
  {
    devShells = fmapSystems (
      { pkgs }: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.nur.repos.liyangau.case-cli
          ];
        };
      }
    );
  };
}
