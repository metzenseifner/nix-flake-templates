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
    traverseSystems =
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
    devShells = traverseSystems (
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
