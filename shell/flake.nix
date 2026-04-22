{
  description = ''
    Use `nix develop` or `nix develop -c $SHELL` to activate me.

    # Add version-controlled source code to inputs like this:
    golangci2-src = {
      url = "github:golangci/golangci-lint?ref=v2.5.0";
      flake = false;
    };

    # Ref inputs in outputs like this
    golangci_lint_v2_from_source = mkGolangciLintFromSourceDerivation {
      src = inputs.golangci2-src;
      version = "2.5.0";
    };
    # or without function abstraction:
    golangci_lint_v2_from_source_derivation = pkgs.buildGoModule {
      pname = "golangci-lint";
      version = "2.5.0";
      src = inputs.golangci2-src;

      vendorHash = null;

      subPackages = [ "cmd/golangci-lint" ];

      ldflags = [
        "-s"
        "-w"
        "-X main.version=2.5.0"
        "-X main.commit=${inputs.golangci2-src.rev or "unknown"}"
        "-X main.date=1970-01-01"
      ];

      postInstall = ''
        mv "$out/bin/golangci-lint" "$out/bin/golangci-lint-v${lib.versions.major "2.5.0"}"
      '';

      meta.platforms = lib.platforms.unix;
    };
  '';
  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/release-25.05"; # or release-25.05
  };

  outputs =
  {
    self,
    nixpkgs,
    systems,
  }:
  let
    traverseSystems =
      f: nixpkgs.lib.genAttrs (import systems) (system: f { inherit system; pkgs = import nixpkgs { inherit system; }; });
  in
  {
    devShells = traverseSystems (
      { pkgs, system }:
      let
          myPackages = with pkgs; [
            hello
          ];
          packageNames = builtins.concatStringsSep " " (map (p: p.name) myPackages);
      in
      {
        default = pkgs.mkShellNoCC {
          packages = myPackages;
          shellHook = ''
          # export PATH=$NEWPATH:$PATH
          echo "🔧 Activated nix shell for system: ${system}"
          echo "📦 Available packages: ${packageNames}"
          echo "🧑🏼‍💻 Available executables from the Nix Store:"
          echo "$PATH" | tr ':' '\n' | grep '^/nix/store' | xargs -I{} sh -c 'ls -1 "{}" 2>/dev/null || true' | xargs || true
          '';
        };
      }
    );
  };
}
