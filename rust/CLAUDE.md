# Claude instructions for this Rust + Nix project

This file tells Claude (and other AI assistants) how this project is wired so it
makes changes that fit the design instead of fighting it.

## Division of labor

* **Cargo owns crate dependencies.** Add/remove crates via `Cargo.toml`; let
  Cargo write `Cargo.lock`.
* **Nix owns the toolchain, system libraries, and the reproducible environment.**
  The Rust toolchain version, OpenSSL, `pkg-config`, etc. live in `flake.nix`.

**Anti-pattern to avoid:** hand-maintaining crate versions or hashes in Nix that
duplicate what's already in `Cargo.lock`. We use [crane], which derives the
dependency layer from `Cargo.lock` directly. There should be no `cargoHash`
strings to babysit.

[crane]: https://github.com/ipetkov/crane

## Files that must be committed

* `Cargo.toml`, `Cargo.lock`
* `flake.nix`, `flake.lock`
* `rust-toolchain.toml`

If you change any of these, commit the lock-file update in the same change.

## Single source of truth for the toolchain

`rust-toolchain.toml` is the only place the Rust channel and components are
declared. `flake.nix` reads it via `pkgs.rust-bin.fromRustupToolchainFile`.
Do **not** add a separate `rust-bin.stable.latest.default` call in the flake.

To bump the toolchain: edit `rust-toolchain.toml`, then `nix develop` (or
`nix flake check`) will pull the new version on next eval.

## Updates are two separate, intentional operations

| Goal               | Command                         | What to review       |
| ------------------ | ------------------------------- | -------------------- |
| Update crates      | `dev-update-crates` (`cargo update`)  | `git diff Cargo.lock` |
| Update flake inputs| `dev-update-flake` (`nix flake update`) | `git diff flake.lock` |

Do not conflate them. Do not let either float automatically (no `--unlocked`
in CI).

## System libraries

Native deps go in `commonBuildInputs` in `flake.nix`; build tools like
`pkg-config` go in `commonNativeBuildInputs`. **Never** rely on ad-hoc env
variables set only in `shellHook` — define env in `commonEnv` so the devShell
and the `nix build` package agree. Divergent env is the trap that makes
`cargo build` work interactively but `nix build` fail (or vice versa).

When adding a crate that links a C library:

1. Add the library to `commonBuildInputs`.
2. If it needs `pkg-config`, it's already in `commonNativeBuildInputs`.
3. If it has a `NO_VENDOR` style env (like `OPENSSL_NO_VENDOR`), set it in
   `commonEnv` so both code paths use the Nix-provided library.

## Dev shell

Enter with `nix develop`, or — preferred — install [direnv] + [nix-direnv] and
run `direnv allow` once; the shell will auto-load on `cd`.

[direnv]: https://direnv.net/
[nix-direnv]: https://github.com/nix-community/nix-direnv

Inside the shell, `dev-help` lists all `dev-*` commands. `rust-analyzer` finds
the pinned std sources via `RUST_SRC_PATH` (set in `commonEnv`).

## Checks

`nix flake check` runs clippy (warnings → errors), `cargo fmt --check`, and
the test suite — using the same toolchain/env as the package build. CI should
run exactly this; do not invent a parallel CI pipeline.

## Binary cache (optional but recommended)

Crane's separate-dependency-layer only pays off across machines if you push to
a binary cache. Set up [Cachix] or a self-hosted [attic] and add the cache to
`nixConfig.extra-substituters` in `flake.nix` once you have one.

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
