# Claude instructions for the Nix overlay on this existing Rust project

This file tells Claude (and other AI assistants) how the Nix-side of this
project is wired so it makes changes that fit the design instead of fighting
it. The Cargo side (`Cargo.toml`, `Cargo.lock`, `src/`) pre-existed and is
owned by the project — Nix is layered on top, not replacing anything.

## Division of labor

* **Cargo owns crate dependencies.** Add/remove crates via `Cargo.toml`; let
  Cargo write `Cargo.lock`. **Do not** mirror crate versions in `flake.nix`.
* **Nix owns the toolchain, system libraries, and the reproducible environment.**
  The Rust toolchain version, OpenSSL, `pkg-config`, etc. live in `flake.nix`
  / `rust-toolchain.toml`.

**Anti-pattern to avoid:** hand-maintaining crate versions or hashes in Nix
that duplicate what's already in `Cargo.lock`. This template uses [crane],
which derives the dependency layer from your existing `Cargo.lock` directly.
There should be no `cargoHash` strings to babysit.

[crane]: https://github.com/ipetkov/crane

## Files added by this template

* `flake.nix`, `flake.lock` — Nix build + dev shell
* `rust-toolchain.toml` — single source of truth for Rust channel + components
* `.envrc` — `use flake` for direnv / nix-direnv
* `.gitignore` — Nix entries (`result`, `result-*`, `.direnv/`); merge with
  any pre-existing `.gitignore`

If the repo already had a `rust-toolchain.toml` or `rust-toolchain` file,
**reconcile them — keep only one**. The one shipped here is what `flake.nix`
reads via `pkgs.rust-bin.fromRustupToolchainFile`.

## Files that must be committed

* `Cargo.toml`, `Cargo.lock` (these already existed)
* `flake.nix`, `flake.lock`
* `rust-toolchain.toml`

## Updates are two separate, intentional operations

| Goal               | Command                                 | What to review        |
| ------------------ | --------------------------------------- | --------------------- |
| Update crates      | `dev-update-crates` (`cargo update`)    | `git diff Cargo.lock` |
| Update flake inputs| `dev-update-flake` (`nix flake update`) | `git diff flake.lock` |

Do not conflate them. Do not let either float automatically.

## System libraries

Native deps the existing crates link against go in `commonBuildInputs` in
`flake.nix`; build tools like `pkg-config` go in `commonNativeBuildInputs`.
**Never** rely on ad-hoc env variables set only in `shellHook` — define env
in `commonEnv` so the devShell and the `nix build` package agree. Divergent
env is the trap that makes `cargo build` work interactively but `nix build`
fail (or vice versa).

When the existing project pulls in a crate that links a C library:

1. Add the library to `commonBuildInputs`.
2. If it needs `pkg-config`, it's already in `commonNativeBuildInputs`.
3. If it has a `NO_VENDOR` style env (like `OPENSSL_NO_VENDOR`), set it in
   `commonEnv` so both code paths use the Nix-provided library.

## Dev shell

Enter with `nix develop`, or — preferred — install [direnv] + [nix-direnv]
and run `direnv allow` once; the shell will auto-load on `cd`.

[direnv]: https://direnv.net/
[nix-direnv]: https://github.com/nix-community/nix-direnv

Inside the shell, `dev-help` lists all `dev-*` commands. `rust-analyzer`
finds the pinned std sources via `RUST_SRC_PATH` (set in `commonEnv`).

## Checks

`nix flake check` runs clippy (warnings → errors), `cargo fmt --check`, and
the test suite — using the same toolchain/env as the package build. If the
existing project has its own CI, prefer running `nix flake check` there over
inventing a parallel pipeline.

## Binary cache (optional but recommended)

Crane's separate-dependency-layer only pays off across machines if you push
to a binary cache. Set up [Cachix] or a self-hosted [attic] and add the cache
to `nixConfig.extra-substituters` in `flake.nix` once you have one.

[Cachix]: https://www.cachix.org/
[attic]: https://github.com/zhaofengli/attic

## When in doubt

* Adding a crate? Edit `Cargo.toml`, run `cargo add` or `cargo build`, commit
  the `Cargo.lock` change. Do not touch `flake.nix`.
* Adding a system library? Edit `flake.nix` (`commonBuildInputs`), run
  `nix flake check`, commit.
* Bumping Rust? Edit `rust-toolchain.toml`, run `nix flake check`, commit.
* Bumping nixpkgs / crane? Run `dev-update-flake`, review `flake.lock`,
  commit.
