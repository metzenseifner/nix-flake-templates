{
  description = ''
    Rust project bootstrap.

    Division of labor:
      * Cargo owns crate dependencies (Cargo.toml / Cargo.lock).
      * Nix owns the toolchain, system libraries, and reproducible env.

    The Rust toolchain is read from rust-toolchain.toml (single source of truth).
    Crate hashes are derived from Cargo.lock by crane (no hand-maintained hashes).
    Build inputs and env vars are declared once and shared by devShell + package
    so `cargo build` in `nix develop` and `nix build` agree.

    Quick start:
      nix develop          # enter dev shell (or `direnv allow` if using nix-direnv)
      nix build            # build the package via crane
      nix flake check      # run clippy, rustfmt, and tests as Nix checks
  '';

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    crane.url = "github:ipetkov/crane";

    nix-derivation-hofs = {
      url = "github:metzenseifner/nix-derivation-hofs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      rust-overlay,
      crane,
      nix-derivation-hofs,
      ...
    }:
    let
      # Functor: lift (pkgs -> outputs) across each flake-exposed system.
      fmapSystems =
        f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
          system:
          f {
            inherit system;
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ rust-overlay.overlays.default ];
            };
          }
        );

      perSystemOutputs =
        { system, pkgs }:
        let
          inherit (nix-derivation-hofs.lib) withHelps mkHelpPkg;

          # ---- Single source of truth for the toolchain ----
          # rust-toolchain.toml is read by both Nix (here) and rustup-style tools.
          rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

          src = craneLib.cleanCargoSource ./.;

          # ---- One place defines build inputs and env for BOTH devShell and package ----
          # This is the anti-trap: avoid divergent env between `nix develop` and `nix build`.
          commonNativeBuildInputs = [
            pkgs.pkg-config
          ];

          commonBuildInputs =
            [
              pkgs.openssl
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.libiconv
            ];

          # Env vars that BOTH the package build and the dev shell must agree on.
          commonEnv = {
            # Force openssl-sys to use the Nix-provided OpenSSL via pkg-config.
            OPENSSL_NO_VENDOR = "1";
            # Point editors / rust-analyzer at the pinned toolchain's std sources.
            RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          };

          commonArgs = {
            inherit src;
            strictDeps = true;
            nativeBuildInputs = commonNativeBuildInputs;
            buildInputs = commonBuildInputs;
          }
          // commonEnv;

          # Crane derives this layer from Cargo.lock — no hand-maintained hashes.
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          crate = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

          # ---- Dev scripts ----
          # Updates are two intentional, separate operations; never auto-floated.
          dev-build = withHelps "Build the project (cargo build)" (
            pkgs.writeShellApplication {
              name = "dev-build";
              runtimeInputs = [ rustToolchain ];
              text = ''cargo build "$@"'';
            }
          );

          dev-run = withHelps "Run the project (cargo run)" (
            pkgs.writeShellApplication {
              name = "dev-run";
              runtimeInputs = [ rustToolchain ];
              text = ''cargo run "$@"'';
            }
          );

          dev-test = withHelps "Run tests (cargo test)" (
            pkgs.writeShellApplication {
              name = "dev-test";
              runtimeInputs = [ rustToolchain ];
              text = ''cargo test "$@"'';
            }
          );

          dev-check = withHelps "Typecheck without building (cargo check)" (
            pkgs.writeShellApplication {
              name = "dev-check";
              runtimeInputs = [ rustToolchain ];
              text = ''cargo check "$@"'';
            }
          );

          dev-lint = withHelps "Lint with clippy, deny warnings" (
            pkgs.writeShellApplication {
              name = "dev-lint";
              runtimeInputs = [ rustToolchain ];
              text = ''cargo clippy --all-targets -- -D warnings "$@"'';
            }
          );

          dev-fmt = withHelps "Format the code (cargo fmt)" (
            pkgs.writeShellApplication {
              name = "dev-fmt";
              runtimeInputs = [ rustToolchain ];
              text = ''cargo fmt "$@"'';
            }
          );

          dev-doc = withHelps "Generate and open documentation" (
            pkgs.writeShellApplication {
              name = "dev-doc";
              runtimeInputs = [ rustToolchain ];
              text = ''cargo doc --open "$@"'';
            }
          );

          dev-clean = withHelps "Clean build artifacts (cargo clean)" (
            pkgs.writeShellApplication {
              name = "dev-clean";
              runtimeInputs = [ rustToolchain ];
              text = ''cargo clean "$@"'';
            }
          );

          dev-update-crates = withHelps "Update Cargo.lock — review the diff before committing" (
            pkgs.writeShellApplication {
              name = "dev-update-crates";
              runtimeInputs = [ rustToolchain ];
              text = ''
                cargo update "$@"
                echo ""
                echo "Cargo.lock updated. Review the diff with: git diff -- Cargo.lock"
              '';
            }
          );

          dev-update-flake = withHelps "Update flake.lock — review the diff before committing" (
            pkgs.writeShellApplication {
              name = "dev-update-flake";
              runtimeInputs = [ pkgs.nix pkgs.git ];
              text = ''
                nix flake update "$@"
                echo ""
                echo "flake.lock updated. Review the diff with: git diff -- flake.lock"
              '';
            }
          );

          devScripts = [
            dev-build
            dev-run
            dev-test
            dev-check
            dev-lint
            dev-fmt
            dev-doc
            dev-clean
            dev-update-crates
            dev-update-flake
          ];

          dev-help = mkHelpPkg {
            inherit pkgs;
            name = "dev-help";
            derivations = devScripts;
          };
        in
        {
          packages = {
            default = crate;
          };

          apps.default = {
            type = "app";
            program = "${crate}/bin/${crate.pname}";
          };

          # `nix flake check` runs these — same env, same toolchain, same inputs.
          checks = {
            inherit crate;
            clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- -D warnings";
              }
            );
            fmt = craneLib.cargoFmt { inherit src; };
            test = craneLib.cargoTest (commonArgs // { inherit cargoArtifacts; });
          };

          devShells.default = craneLib.devShell (
            {
              # Inherit nativeBuildInputs/buildInputs from the package so env hooks
              # (pkg-config, etc.) set the same PKG_CONFIG_PATH in shell and build.
              inputsFrom = [ crate ];

              packages = devScripts ++ [ dev-help ];

              shellHook = ''
                echo "Rust dev shell (${system})"
                echo "$(rustc --version)"
                echo ""
                echo "Run dev-help for available commands."
              '';
            }
            // commonEnv
          );
        };

      # Compute each system's outputs once, project each field across systems.
      perSystem = fmapSystems perSystemOutputs;
      project = field: builtins.mapAttrs (_: out: out.${field}) perSystem;
    in
    {
      packages = project "packages";
      apps = project "apps";
      checks = project "checks";
      devShells = project "devShells";
    };
}
