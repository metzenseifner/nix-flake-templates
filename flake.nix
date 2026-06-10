{
  description = "A collection of project templates";

  outputs =
    { self }:
    {
      templates = {
        letter = {
          path = ./letter;
          description = "A Markdown to PDF over LuaLaTeX Flake for business letters";
        };
        time = {
          path = ./time;
          description = "A flake that transforms builtins.currentTime into a variety of formats";
        };
        pi5 = {
          path = ./pi5;
          description = "A minimal Pi 5 SD Card Image Flake";
        };
        minimal = {
          path = ./minimal;
          description = "A minimal flake.";
        };
        tart-builders = {
          path = ./tart-builders;
          description = "Create VM Builders with Tart";
        };
        aws = {
          path = ./aws;
          description = "Create AWS CLI shell to help setup";
        };
        nur = {
          path = ./nur;
          description = "Use packages available on NUR";
        };
        local = {
          path = ./local;
          description = "Use local package default.nix";
        };
        go = {
          path = ./go;
          description = "Create a Go with parameterized golangci-lint v1 or v2";
        };
        python = {
          path = ./python;
          description = "Create python 3.12 environment with libraries";
        };
        shell = {
          path = ./shell;
          description = "Use packages available on nixpkgs";
        };
        docker = {
          path = ./docker;
          description = "Build Docker images with Nix";
        };
        server = {
          path = ./server;
          description = "Manage NixOS server remotely";
        };
        nixos-system = {
          path = ./nixos-system;
          description = "Minimal NixOS system for any architecture";
        };
        ipad = {
          path = ./ipad;
          description = "Self-contained NixOS for UTM SE on iPad";
        };
        dynatrace = {
          path = ./dynatrace;
          description = "Dynatrace app development with dtp-cli";
        };
        dynatrace-golangci-lint = {
          path = ./dynatrace-golangci-lint;
          description = "Create a shell with golangci-lint built from source for a specific version and exec string read from Dockerfile";
        };
        mikefarah = {
          path = ./mikefarah;
          description = "Create a shell with Mike Farah's jq and yq";
        };
        kubernetes = {
          path = ./kubernetes;
          description = "Kubernetes development environment with AWS EKS access";
        };
        zero2prod-rust = {
          path = ./zero2prod-rust;
          description = "Rust project with Nix integration matching closely the Zero to Production in Rust Book Specifications";
          welcomeText = ''
            Zero to Production in Rust bootstrap initialized.

             The book's integration tests won't run in the Nix sandbox as-is.
             This doesn't bite in chapter 1, but from chapter 3 onward,
             zero2prod's tests spin up the app and talk to a live Postgres
             (launched via scripts/init_db.sh in Docker). The Nix build sandbox
             has no network and no running services, so the moment you write
             those tests, your nextest check will start failing — not because
             the code is wrong, but because the database isn't there. You have
             three realistic options: run integration tests outside Nix in the
             devShell (book-style, simplest — keep the Nix check limited to
             unit tests via nextest filter expressions); start an ephemeral
             Postgres inside the check derivation (pkgs.postgresql, initdb +
             pg_ctl against a Unix socket in a preCheck hook — fully hermetic,
             very Nix-idiomatic, some setup work); or a NixOS VM test for the
             full integration suite (the heavyweight, most rigorous option).
             Worth deciding before you hit chapter 3 rather than when CI
             suddenly goes red.
          '';
        };
        rust = {
          path = ./rust;
          description = "Rust project bootstrap (crane + rust-toolchain.toml). Includes placeholder Cargo.toml and src/main.rs.";
          welcomeText = ''
            Rust bootstrap initialized.

            Files copied:
              flake.nix, flake.lock        - Nix build + dev shell (crane)
              rust-toolchain.toml          - single source of truth for the toolchain
              Cargo.toml, Cargo.lock, src/ - placeholder hello-world crate
              .envrc, .gitignore           - direnv + ignores
              CLAUDE.md                    - AI-assistant guidance

            Next steps:
              direnv allow      # or: nix develop
              dev-help          # list dev-* commands

            If you wanted to add Nix to an EXISTING Cargo project instead,
            use the `rust-integrate` template variant.
          '';
        };
        rust-integrate = {
          path = ./rust-integrate;
          description = "Add Nix (crane + rust-toolchain.toml) to an EXISTING Rust project. Ships only flake/dev-shell files — no Cargo.toml or src/.";
          welcomeText = ''
            Rust + Nix overlay initialized for an existing Cargo project.

            Files copied (Nix-side only):
              flake.nix, flake.lock        - Nix build + dev shell (crane)
              rust-toolchain.toml          - single source of truth for the toolchain
              .envrc, .gitignore           - direnv + ignores
              CLAUDE.md                    - AI-assistant guidance

            Your existing Cargo.toml / Cargo.lock / src/ were NOT touched.

            Integration checklist:
              1. Merge .gitignore entries with any existing .gitignore.
              2. Reconcile rust-toolchain.toml with any pre-existing toolchain
                 file in the repo — keep only one.
              3. Add native deps to commonBuildInputs in flake.nix.
              4. nix flake check   # verify clippy / fmt / tests under Nix
              5. git add the new files and commit.
          '';
        };
      };
      defaultTemplate = self.templates.shell;
    };
}
