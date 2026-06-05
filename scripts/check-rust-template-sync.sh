#!/usr/bin/env bash
# Verify rust/flake.nix and rust-integrate/flake.nix agree below the description.
#
# The two templates intentionally diverge only in the top-of-file `description`
# string. Everything from the `inputs = { ... }` line onwards must match
# byte-for-byte so the build logic stays in sync across variants.
#
# Exit codes:
#   0  files agree (or only the description differs)
#   1  files have diverged below the description block
#   2  expected files are missing
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
A="$REPO_ROOT/rust/flake.nix"
B="$REPO_ROOT/rust-integrate/flake.nix"

if [[ ! -f "$A" ]] || [[ ! -f "$B" ]]; then
  echo "error: expected both $A and $B to exist" >&2
  exit 2
fi

# Print everything from the first `  inputs = ` line to EOF.
extract_body() {
  awk '/^  inputs = / { found = 1 } found' "$1"
}

if ! diff_output="$(diff -u \
    --label "rust/flake.nix (body)" \
    --label "rust-integrate/flake.nix (body)" \
    <(extract_body "$A") <(extract_body "$B"))"; then
  cat >&2 <<EOF
error: rust/flake.nix and rust-integrate/flake.nix have diverged below
       the description block. Only the top-of-file \`description = ''...'';\`
       is allowed to differ between the two variants.

Diff (- rust, + rust-integrate):

$diff_output

Fix: pick whichever side is correct and mirror the change to the other file,
then re-stage and commit.
EOF
  exit 1
fi
