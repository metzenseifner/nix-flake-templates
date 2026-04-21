{
  description = ''
    Rust development environment with a unified project CLI.

    Use `nix develop` or `nix develop -c $SHELL` to activate.
  '';

  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    nix-derivation-hofs = {
      url = "git+ssh://git@github.com/metzenseifner/nix-derivation-hofs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      rust-overlay,
      nix-derivation-hofs,
    }:
    let
      forEachSystem =
        f:
        nixpkgs.lib.genAttrs (import systems) (
          system:
          f {
            inherit system;
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ rust-overlay.overlays.default ];
            };
          }
        );
    in
    {
      devShells = forEachSystem (
        { pkgs, system }:
        let
          # Use stable Rust toolchain with clippy and rustfmt
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "rust-analyzer"
              "clippy"
              "rustfmt"
            ];
          };

          # --- Unified CLI scripts ---
          # These use a dev-* prefix so they won't collide with anything
          # and can be the same across language templates.

          inherit (nix-derivation-hofs.lib) withDocs mkHelpPkg;
          dev-init = withDocs "Initialize a new project" (
            pkgs.writeShellScriptBin "dev-init" ''
              set -euo pipefail
              if [ -f Cargo.toml ]; then
                echo "Cargo.toml already exists. Aborting."
                exit 1
              fi
              cargo init "''${@:-.}"
              echo "Project initialized."
            ''
          );

          dev-deps = withDocs "Fetch/build dependencies" (
            pkgs.writeShellScriptBin "dev-deps" ''
              set -euo pipefail
              cargo fetch "$@"
              echo "Dependencies fetched."
            ''
          );

          dev-update = withDocs "Update dependencies" (
            pkgs.writeShellScriptBin "dev-update" ''
              set -euo pipefail
              cargo update "$@"
              echo "Dependencies updated."
            ''
          );

          dev-build = withDocs "Build the project" (
            pkgs.writeShellScriptBin "dev-build" ''
              set -euo pipefail
              cargo build "$@"
            ''
          );

          dev-test = withDocs "Run tests" (
            pkgs.writeShellScriptBin "dev-test" ''
              set -euo pipefail
              cargo test "$@"
            ''
          );

          dev-lint = withDocs "Lint the project" (
            pkgs.writeShellScriptBin "dev-lint" ''
              set -euo pipefail
              cargo clippy "$@"
            ''
          );

          dev-fmt = withDocs "Format the code" (
            pkgs.writeShellScriptBin "dev-fmt" ''
              set -euo pipefail
              cargo fmt "$@"
            ''
          );

          dev-run = withDocs "Run the project" (
            pkgs.writeShellScriptBin "dev-run" ''
              set -euo pipefail
              cargo run "$@"
            ''
          );

          dev-clean = withDocs "Clean the build artifacts" (
            pkgs.writeShellScriptBin "dev-clean" ''
              set -euo pipefail
              cargo clean "$@"
              echo "Build artifacts cleaned."
            ''
          );

          dev-check = withDocs "Typecheck without building" (
            pkgs.writeShellScriptBin "dev-check" ''
              set -euo pipefail
              cargo check "$@"
            ''
          );

          dev-doc = withDocs "Generate and open documentation" (
            pkgs.writeShellScriptBin "dev-doc" ''
              set -euo pipefail
              cargo doc --open "$@"
            ''
          );

          devScripts = [
            dev-init
            dev-deps
            dev-update
            dev-build
            dev-test
            dev-lint
            dev-fmt
            dev-run
            dev-clean
            dev-check
            dev-doc
          ];

          dev-help = mkHelpPkg {
            inherit pkgs;
            name = "dev-help";
            derivations = devScripts;
          };

          myPackages = [
            rustToolchain
            pkgs.pkg-config
            pkgs.openssl
          ]
          ++ devScripts
          ++ [ dev-help ];

          packageNames = builtins.concatStringsSep " " (map (p: p.name) myPackages);
        in
        {
          default = pkgs.mkShellNoCC {
            packages = myPackages;

            # Needed for some crates that link against system libs
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
              pkgs.openssl
            ];

            shellHook = ''
              echo "🔧 Activated Rust dev shell for system: ${system}"
              echo "🦀 Rust: $(rustc --version)"
              echo ""
              echo "Run dev-help for available commands."
            '';
          };
        }
      );
    };
}
