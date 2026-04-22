{
  description = ''
    Use `nix develop` or `nix develop -c $SHELL` to activate me.

    Strategies to enable toggling between golangci-lint versions:
    1. Proxy script wrapper to serve as dispatcher to v1 or v2
    2. Helper shell function that takes version as arg to swap out a private bin symlink.
    3. Split dev shells and choose at nix develop time: nix develop .#v1 | nix develop .#v2

    This flake uses strategy 3.
  '';
  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/release-25.05";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs =
    inputs@{
      self,
      nixpkgs,
      systems,
      # note: we don't need to destructure nixpkgs-unstable here; we'll use inputs."nixpkgs-unstable"
      # but we do need an ellipsis to make outputs accept extra inputs like nixpkgs-unstable
      ...
    }:
    let
      traverseSystems =
        f:
        nixpkgs.lib.genAttrs (import systems) (
          system:
          f {
            inherit system;
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };

            pkgsUnstable = import inputs."nixpkgs-unstable" {
              inherit system;
              config.allowUnfree = true;
            };

          }
        );
    in
    {
      devShells = traverseSystems (
        {
          pkgs,
          pkgsUnstable,
          system,
        }:
        let
          lib = pkgs.lib;

          # platform mapping + mkGolangciLintDerivation stay as you already have them
          platform =
            {
              "x86_64-linux" = {
                os = "linux";
                arch = "amd64";
              };
              "aarch64-linux" = {
                os = "linux";
                arch = "arm64";
              };
              "x86_64-darwin" = {
                os = "darwin";
                arch = "amd64";
              };
              "aarch64-darwin" = {
                os = "darwin";
                arch = "arm64";
              };
            }
            .${pkgs.stdenv.hostPlatform.system}
              or (throw "Unsupported system: ${pkgs.stdenv.hostPlatform.system}");

          # (fetches tarball, unpacks, installs the real binary)
          mkGolangciLintDerivation =
            { version, sha256s }:
            pkgs.stdenv.mkDerivation {
              pname = "golangci-lint";
              inherit version;

              src = pkgs.fetchurl {
                url = "https://github.com/golangci/golangci-lint/releases/download/v${version}/golangci-lint-${version}-${platform.os}-${platform.arch}.tar.gz";
                hash =
                  sha256s.${pkgs.stdenv.hostPlatform.system}
                    or (throw "Missing hash for ${pkgs.stdenv.hostPlatform.system} (golangci-lint v${version})");
              };

              phases = [
                "unpackPhase"
                "installPhase"
              ];
              installPhase = ''
                set -eu
                mkdir -p "$out/bin"
                BIN="golangci-lint"
                if [ ! -e "$BIN" ]; then
                  if [ -e "bin/golangci-lint" ]; then
                    BIN="bin/golangci-lint"
                  else
                    echo "Contents of source root (for debugging):"
                    ls -la
                    echo "Could not find golangci-lint binary in source root"
                    exit 1
                  fi
                fi
                install -m 0755 "$BIN" "$out/bin/golangci-lint-v${lib.versions.major version}"
              '';
              meta.platforms = [ pkgs.stdenv.hostPlatform.system ];
            };

          # Your two versions (fill missing hashes as needed)
          golangci_lint_v1 = mkGolangciLintDerivation {
            version = "1.64.8";
            sha256s = {
              x86_64-linux = ""; # fill me
              aarch64-linux = "sha256-<fill-me>";
              x86_64-darwin = "sha256-<fill-me>";
              aarch64-darwin = "sha256-cFQ9IeWwKpQHm+iqESZ6WwYIZVg+M3/naNObXT4vrx8=";
            };
          };

          golangci_lint_v2 = mkGolangciLintDerivation {
            version = "2.5.0";
            sha256s = {
              x86_64-linux = ""; # fill me
              aarch64-linux = "sha256-<fill-me>";
              x86_64-darwin = "";
              aarch64-darwin = "sha256-Czy9wqJHL2C1OOvMsbLhrl2TigUcAQWRqmjG79NwZnI=";
            };
          };

          # a tiny wrapper that exposes the chosen version as "golangci-lint"
          # wraps an existing package (no fetching/building of the tool itself)
          # It creates a tiny Nix package (a "derivatoin") that installs an executable named golangci-lint that simply executes an executable from another derivation.
          mkDefaultLintDerivation =
            drv: binName:
            pkgs.writeShellScriptBin "golangci-lint" ''
                set -euo pipefail
                
              target="${drv}/bin/${binName}"
                if [ ! -x "$target" ]; then
                  echo "golangci-lint wrapper error: $target not found or not executable" >&2
                  exit 127
                fi

                exec -a golangci-lint "${drv}/bin/${binName}" "$@"
                # -a golangci-lint sets argv[0] (process name) to golangci-lint.
                # "${drv}/bin/${binName}" is the fully-qualified store path to the actual binary
                # "$@" forwards all user-provided arguments.
            '';

          golangci_lint_v1_default = mkDefaultLintDerivation golangci_lint_v1 "golangci-lint-v1";
          golangci_lint_v2_default = mkDefaultLintDerivation golangci_lint_v2 "golangci-lint-v2";

          # -- DRY shellHook: shared between all shells --
          commonShellHook = packageNames: ''
            echo "🔧 Activated nix shell for system: ${system}"
            echo "📦 Available packages: ${packageNames}"
            echo "🧑🏼‍💻 Available executables:"
            echo "$PATH" | tr ':' '\n' | grep '^/nix/store' | xargs -I{} sh -c 'ls -1 "{}" 2>/dev/null || true' | xargs || true
          '';

          # -- helper to build a shell for a chosen version --
          mkDevShell =
            {
              drv,
              defaultWrapper,
              extraPackages ? [ ],
            }:
            let
              pkgsList = [
                drv
                defaultWrapper
              ]
              ++ extraPackages;
              packageNames = builtins.concatStringsSep " " (map (p: p.name) pkgsList);
            in
            pkgs.mkShellNoCC {
              packages = pkgsList;
              shellHook = commonShellHook packageNames;
            };

          extraPackages = with pkgsUnstable; [
            github-copilot-cli
            bats
          ];
        in
        {
          # Mutually exclusive shells where "golangci-lint" maps to one version
          v1 = mkDevShell {
            drv = golangci_lint_v1;
            defaultWrapper = golangci_lint_v1_default;
            inherit extraPackages;
          };
          v2 = mkDevShell {
            drv = golangci_lint_v2;
            defaultWrapper = golangci_lint_v2_default;
            inherit extraPackages;
          };

          # Optional: pick one as default for `nix develop` without selector
          default = self.devShells.${system}.v2;
        }
      );
    };
}
