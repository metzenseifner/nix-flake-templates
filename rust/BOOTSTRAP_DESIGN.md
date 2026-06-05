# Nix Integration with Rust
A good approach:
Cargo owns your crate dependencies; Nix owns the toolchain, system libraries, and the reproducible environment.
>[!warning] The classic anti-pattern is hand-maintaining crate versions or hashes in Nix that duplicate what's already in `Cargo.lock`.

## How
### **Commit every lock file.**
`Cargo.lock` and `flake.lock` both go in version control.
### Define the toolchain once and have Nix read it.
Put your Rust version in `rust-toolchain.toml` and have your flake consume _that file_ rather than specifying the version separately in Nix.
### **Let the build tool read `Cargo.lock` instead of hand-maintaining hashes.**
If you use `crane`, it derives its dependency layer from `Cargo.lock` directly. If you use nixpkgs' `buildRustPackage`, prefer `cargoLock.lockFile = ./Cargo.lock;` over a manually-updated `cargoHash`—it reads the lock file so you're not babysitting a hash that breaks on every dependency bump. Either way, Cargo stays the source of truth for crates and Nix follows it automatically.
### Keep flake inputs deduplicated.
Use `follows` so your Nix tooling shares one nixpkgs instead of pulling several copies—e.g. `inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs"`
### **Declare native deps in Nix, and keep env vars identical across dev shell and build.**
System libraries (openssl, sqlite, etc.) go in `buildInputs`, with `pkg-config` in `nativeBuildInputs`—not in ad hoc shell scripting. 
>[!warning] The trap is when your `nix develop` shell and your package derivation set different env (things like `OPENSSL_NO_VENDOR` or `PKG_CONFIG_PATH`), so `cargo build` works interactively but the Nix build fails, or vice versa. Define them in one place both consume.
### **Treat updates as two separate, intentional operations.**
`cargo update` for crates (review the `Cargo.lock` diff), `nix flake update` for inputs (review the `flake.lock` diff). 
>[!warning] Don't let either float automatically, and don't conflate them.

### **Make the dependency caching actually pay off with a binary cache.**
The main reason to use crane's separate-dependency-layer approach is to avoid rebuilding all deps on every source change—but that benefit only crosses machines and CI if you push to a binary cache (**Cachix**, or a **self-hosted attic**). Without one, each machine still rebuilds from scratch.

## Extra Convenience Ideas
### auto load dev environment + cache when entering directory
 `direnv` + `nix-direnv` so the environment auto-loads and stays cached when you `cd` in, and pointing rust-analyzer at the Nix-provided `RUST_SRC_PATH` so your editor matches the pinned toolchain.
 
