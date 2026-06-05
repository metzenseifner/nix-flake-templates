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

    Maintaining dependencies over time
    ----------------------------------
    Three buckets define what the project needs from the system. Putting each
    new dep in the right bucket is what keeps the closure honest and avoids
    "works in `nix develop`, fails in `nix build`" drift.

      commonNativeBuildInputs  Tools that run on the BUILD host during compile
                               (pkg-config, cmake, protoc, bindgen). Not linked
                               into the binary, not in the runtime closure.
                               Cross-compilation: these are build-platform tools.

      commonBuildInputs        Libraries linked into the binary OR needed at
                               runtime (openssl, sqlite, libpq). Also the
                               answer when a -sys crate's build.rs needs to
                               locate headers/libs. Cross-compilation: these
                               are target-platform libs.

      commonEnv                Env vars BOTH `nix build` and `nix develop` must
                               agree on (OPENSSL_NO_VENDOR, PROTOC, LIBCLANG_PATH,
                               RUST_SRC_PATH). The anti-trap: vars set only in
                               shellHook drift away from what `nix build` sees.

    Extending:
      * Pure-Rust crate              `cargo add`, commit Cargo.lock. Done — do
                                     NOT touch flake.nix.
      * Crate with a -sys companion  `cargo add`, then add the C library to
                                     commonBuildInputs and any required env
                                     (OPENSSL_NO_VENDOR, PROTOC=..., etc.) to
                                     commonEnv. Re-run `nix flake check`.
      * Build-time tool only         commonNativeBuildInputs — keeps it out of
                                     the runtime closure.
      * Test-only system dep         Still commonBuildInputs. `nix flake check`
                                     runs tests under the SAME buildInputs as
                                     `nix build`; there is no separate test
                                     bucket. Put rust-side test helpers
                                     (cargo-nextest, cargo-insta) in the
                                     devShell's extra packages, not here.
      * Runtime-only system dep      Still commonBuildInputs. Crane's package
                                     closure is what gets shipped, and anything
                                     reachable from buildInputs is reachable
                                     at runtime.
      * Toolchain bump               Edit rust-toolchain.toml, `nix flake
                                     check`, commit. Never bump it in flake.nix.
      * Flake input bump             `dev-update-flake` (nix flake update),
                                     commit flake.lock SEPARATELY from any
                                     Cargo.lock change.

    Trimming:
      * Remove a crate               `cargo remove`, commit Cargo.lock. If the
                                     crate was the only user of a native dep,
                                     delete the matching entries from
                                     commonBuildInputs / commonEnv too.
      * Audit periodically           Grep Cargo.lock for `*-sys` crates and
                                     cross-check against commonBuildInputs.
                                     Missing entry → silent vendored fallback
                                     or breakage on a fresh machine. Extra
                                     entry → harmless but bloats the closure.

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
          # pkg-config + openssl + OPENSSL_NO_VENDOR are pre-wired as a set because
          # openssl-sys is the most common native dep in the Rust ecosystem (reqwest
          # default features, git2, native-tls, ...). Drop all three if you stay on
          # pure-rustls; keep all three if you add anything that pulls in openssl-sys.
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
            # Use the Nix-provided OpenSSL instead of letting openssl-sys build its vendored copy.
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
