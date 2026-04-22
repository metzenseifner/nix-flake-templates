# Key improvements to consider
#
# -  Share the perSystemOutputs computation across projections using the mapAttrs pattern shown in the final comment, avoiding redundant thunk allocation.
# -  Replace rec with explicit let bindings for the scripts set to avoid accidental infinite recursion as the set grows.
# -  Add default to apps (e.g. apps.default = apps.help;) so nix run works without specifying a name.
# -  Add formatter output (e.g. nixfmt or alejandra) so nix fmt works out of the box.
# -  Consider flake-parts if the project grows — it uses a module-system approach (essentially a free monad over the flake schema) that scales better than manual projections for large multi-output flakes, while still avoiding the merge-opacity of flake-utils.
{
  description = "Minimal Flake";

  inputs = {
    # Typos on lefthand side will silently fail to bind correctly.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    # Pattern: inputs@{ self, ... } uses an "as-pattern" (alias pattern),
    # binding the full attribute set to `inputs` while destructuring `self`.
    # The `...` makes the pattern open (existentially quantified row),
    # so additional input attrs (e.g. nixpkgs) are accessible via `inputs.xyz`
    # without needing to enumerate them here.
    #
    # Why: Decouples the destructuring site from the full input schema.
    # Adding a new input doesn't require updating the pattern — a form of
    # open-world extensibility akin to row polymorphism.
    inputs@{ self, ... }:
    let

      # ── traverseSystems : (Pkgs → AttrSet) → AttrSet(System, AttrSet) ──────────
      #
      # This is the core "system-indexed product" combinator.
      # Algebraically: given a morphism f : Pkgs → A,
      # produce a record (product type) indexed by System:
      #
      #   ∏_{s ∈ flakeExposed} f(legacyPackages.s)
      #
      # Implementation:
      #   - `genAttrs` constructs a record from a list of keys and a function,
      #     i.e. genAttrs : List(K) → (K → V) → Record(K, V)
      #   - `systems.flakeExposed` is the canonical list of systems Nix flakes
      #     expect outputs to be keyed by (x86_64-linux, aarch64-darwin, etc.).
      #   - The callback receives `legacyPackages.${system}`, which is the
      #     fully instantiated nixpkgs package set for that system.
      #
      # Why this over flake-utils.eachDefaultSystem:
      #   1. Zero extra inputs — no transitive dependency on flake-utils,
      #      which itself pins a systems list and adds indirection.
      #   2. Transparency — the system list is drawn directly from nixpkgs,
      #      so it stays in sync with upstream without a separate `systems` flake.
      #   3. Simpler algebra — flake-utils merges a *record of records* via
      #      deep-merge, which is partial (can silently shadow keys).
      #      Here, each output attr is an explicit projection (see below),
      #      making the structure fully visible and compositionally safe.
      #   4. Debuggability — no hidden `eachSystem` fold; the data flow is
      #      a plain function application, trivially traceable in `nix repl`.
      #
      traverseSystems =
        f:
        inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed (
          system: f inputs.nixpkgs.legacyPackages.${system}
        );

      # ── perSystemOutputs : System → Pkgs → Record { packages, apps, devShells } ────
      #
      # This is the "fibre" of the system-indexed bundle:
      # for a given system and its package set, produce ALL per-system outputs
      # as a single coherent record (product type).
      #
      # Algebraically, perSystemOutputs defines a dependent pair:
      #   (s : System) × (pkgs : Pkgs(s)) → { packages : A, apps : B, ... }
      #
      # Crucially, everything for one system is defined together in one
      # lexical scope, so packages can reference each other (see `scripts.help`
      # used in both `apps` and `devShells`). This is the "fiber bundle"
      # pattern — each fiber (system) is self-contained.
      #
      # Why this over flake-utils:
      #   flake-utils.eachDefaultSystem expects you to return a flat merged
      #   attrset. If you accidentally produce clashing keys across output
      #   types (e.g. `packages.foo` vs `apps.foo`), the merge is ambiguous.
      #   Here, the record structure is explicit — no implicit merging.
      #
      perSystemOutputs =
        system: pkgs:
        let
          # ── scripts : Record { help, default } ──────────────────────────
          #
          # `rec` makes this a recursive attribute set, allowing attrs to
          # reference each other. Algebraically this is a fixpoint:
          #   scripts = fix(self → { help = ...; default = self.help; })
          #
          # `default` is an alias (a section/retract in categorical terms)
          # pointing to `help`, so `nix run` without a name resolves here.
          #
          # Possible improvement: `rec` is a blunt instrument — it makes
          # ALL attrs mutually visible, which can cause infinite recursion
          # if misused. For larger sets, prefer explicit `let` bindings
          # or `lib.fix` with an overlay-style pattern for controlled
          # recursion.
          #
          scripts = rec {
            help = pkgs.writeShellScriptBin "my-help" ''

            '';
            default = help;
          };

          # ── mkBinApp : Derivation → String → App ────────────────────────
          #
          # A "smart constructor" (in Haskell parlance) that encapsulates
          # the Nix flake app schema { type = "app"; program = <path>; }.
          #
          # Algebraically: mkBinApp : Drv × BinName → App
          # This is a morphism in the category of flake output types,
          # mapping (derivation, binary name) pairs to well-formed app records.
          #
          # Why: Eliminates repeated string interpolation and ensures the
          # `type = "app"` tag is always present — a lightweight "phantom
          # type" guarantee at the value level.
          #
          # Possible improvement: Add a runtime assertion that
          # `${drv}/bin/${bin}` actually exists, e.g. via
          #   assert builtins.pathExists "${drv}/bin/${bin}";
          # to fail at eval time rather than at run time.
          # (Note: this only works for already-built drvs in practice;
          # for general use, a `passthru.tests` check is more idiomatic.)
          #
          mkBinApp = drv: bin: {
            type = "app";
            program = "${drv}/bin/${bin}";
          };
        in
        # The returned record is the "total space" for this system fiber.
        {
          packages = scripts;
          apps = {
            help = mkBinApp scripts.help "my-help";
          };
          devShells.default = pkgs.mkShell {
            packages = [
              scripts.help
            ];
          };
        };
    in
    {
      # ── Projections over Record(System) ────────────────────────────────────
      #
      # Each top-level output attr is a π-projection (product elimination)
      # from the perSystemOutputs bundle:
      #
      #   packages = π_packages ∘ (∏_s perSystemOutputs(s))
      #   apps     = π_apps     ∘ (∏_s perSystemOutputs(s))
      #
      # i.e., for each system s, we compute the full fiber via `perSystemOutputs`,
      # then project out just the `.packages` (or `.apps`, etc.) component.
      #
      # Why explicit projections instead of a single mapAttrs + deep-merge:
      #   1. Clarity — you see exactly which output types are exported.
      #      Commenting out `devShells` (as done below) is trivial and
      #      has zero effect on other outputs. With flake-utils' merge
      #      approach, disabling one output type requires editing the
      #      inner function, not the outer wiring.
      #   2. Type safety — each projection has a clear type signature.
      #      The flake schema expects `packages.<system>.<name>`, and
      #      this structure guarantees it by construction.
      #   3. Laziness-friendly — Nix is lazy, so unevaluated projections
      #      (commented-out lines) impose zero cost. The `perSystemOutputs` call
      #      is re-invoked per projection, but thanks to Nix's thunk
      #      sharing within each `traverseSystems` call, in practice the
      #      attribute set is built once per system per output type.
      #
      # Trade-off / possible improvement:
      #   Each `traverseSystems` call independently invokes `perSystemOutputs`,
      #   meaning `perSystemOutputs` is called N×M times (N systems × M output
      #   types). While Nix's laziness means only accessed attrs are
      #   forced, the intermediate records are not shared across
      #   projections. A more efficient (but less readable) approach:
      #
      #     let allOutputs = traverseSystems (pkgs:
      #           perSystemOutputs pkgs.system pkgs);
      #     in {
      #       packages  = mapAttrs (_: v: v.packages)  allOutputs;
      #       apps      = mapAttrs (_: v: v.apps)      allOutputs;
      #       devShells = mapAttrs (_: v: v.devShells)  allOutputs;
      #     };
      #
      #   This computes the full bundle once per system and then projects,
      #   achieving sharing across output types — analogous to computing
      #   a product once and applying multiple projections, rather than
      #   recomputing the product for each projection.
      #
      packages = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).packages);
      apps = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).apps);
      # devShells = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).devShells);
      # checks = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).checks);
    };
}
