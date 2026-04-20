{
  description = ''
    Rust development environment with a unified project CLI.

    Use `nix develop` or `nix develop -c $SHELL` to activate.

    Unified CLI commands (same across language templates):
      dev-init     - Initialize a new project (cargo init)
      dev-deps     - Fetch/build dependencies (cargo fetch)
      dev-update   - Update dependencies (cargo update)
      dev-build    - Build the project (cargo build)
      dev-test     - Run tests (cargo test)
      dev-lint     - Lint the project (cargo clippy)
      dev-fmt      - Format code (cargo fmt)
      dev-run      - Run the project (cargo run)
      dev-clean    - Clean build artifacts (cargo clean)
      dev-check    - Type-check without building (cargo check)
      dev-doc      - Generate documentation (cargo doc --open)
      dev-help     - Show this help
  '';

  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      rust-overlay,
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

          dev-init = pkgs.writeShellScriptBin "dev-init" ''
            set -euo pipefail
            if [ -f Cargo.toml ]; then
              echo "Cargo.toml already exists. Aborting."
              exit 1
            fi
            cargo init "''${@:-.}"
            echo "Project initialized."
          '';

          dev-deps = pkgs.writeShellScriptBin "dev-deps" ''
            set -euo pipefail
            cargo fetch "$@"
            echo "Dependencies fetched."
          '';

          dev-update = pkgs.writeShellScriptBin "dev-update" ''
            set -euo pipefail
            cargo update "$@"
            echo "Dependencies updated."
          '';

          dev-build = pkgs.writeShellScriptBin "dev-build" ''
            set -euo pipefail
            cargo build "$@"
          '';

          dev-test = pkgs.writeShellScriptBin "dev-test" ''
            set -euo pipefail
            cargo test "$@"
          '';

          dev-lint = pkgs.writeShellScriptBin "dev-lint" ''
            set -euo pipefail
            cargo clippy "$@"
          '';

          dev-fmt = pkgs.writeShellScriptBin "dev-fmt" ''
            set -euo pipefail
            cargo fmt "$@"
          '';

          dev-run = pkgs.writeShellScriptBin "dev-run" ''
            set -euo pipefail
            cargo run "$@"
          '';

          dev-clean = pkgs.writeShellScriptBin "dev-clean" ''
            set -euo pipefail
            cargo clean "$@"
            echo "Build artifacts cleaned."
          '';

          dev-check = pkgs.writeShellScriptBin "dev-check" ''
            set -euo pipefail
            cargo check "$@"
          '';

          dev-doc = pkgs.writeShellScriptBin "dev-doc" ''
            set -euo pipefail
            cargo doc --open "$@"
          '';

          dev-help = pkgs.writeShellScriptBin "dev-help" ''
            cat <<'HELP'
            Unified dev CLI commands:

              dev-init     Initialize a new project
              dev-deps     Fetch/build dependencies
              dev-update   Update dependencies
              dev-build    Build the project
              dev-test     Run tests
              dev-lint     Lint the project
              dev-fmt      Format code
              dev-run      Run the project
              dev-clean    Clean build artifacts
              dev-check    Type-check without building
              dev-doc      Generate and open documentation
              dev-help     Show this help
            HELP
          '';

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
            dev-help
          ];

          myPackages = [
            rustToolchain
            pkgs.pkg-config
            pkgs.openssl
          ] ++ devScripts;

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
