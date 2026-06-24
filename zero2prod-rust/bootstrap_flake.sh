# Day-0 Steps (Ensure the following)
[ -f Cargo.toml ] || cargo init .

# git-track Cargo.toml for hash
git add Cargo.toml

# git-track Cargo.lock for hash
cargo generate-lockfile; git add Cargo.lock
# deny.toml committed; else cargo deny init, then commit

cargo deny init; git add deny.toml

# .gitignore contains result and result-* as Nix will output build artifacts there.

nix flake check --all-systems # check aforementioned  (or e.g. check for deny.toml by running nix build .#checks.<sys>.deny)
