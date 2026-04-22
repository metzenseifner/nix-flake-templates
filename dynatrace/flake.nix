{
  description = "Development environment for Dynatrace apps with dtp-cli";
  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
    }:
    let
      traverseSystems =
        f:
        nixpkgs.lib.genAttrs (import systems) (
          system:
          f {
            inherit system;
            pkgs = import nixpkgs { inherit system; };
          }
        );
    in
    {
      devShells = traverseSystems (
        { pkgs, system }:
        let
          bootstrap-dynatrace-app = pkgs.writeShellScriptBin "bootstrap-dynatrace-app" ''
            cmd='npx dt-app@latest create --environment-url https://vzx38435.dev.apps.dynatracelabs.com "$@"'
            echo "$cmd"
            eval "$cmd"
          '';

          myPackages = with pkgs; [
            nodejs_22
            git
            bootstrap-dynatrace-app
          ];
          packageNames = builtins.concatStringsSep " " (map (p: p.name) myPackages);
        in
        {
          default = pkgs.mkShellNoCC {
            packages = myPackages;
            shellHook = ''
              # Install dtp-cli globally if not already present
              if ! command -v dt-app &> /dev/null; then
                echo "📦 Installing @dynatrace-sdk/dt-app (dtp-cli)..."
                npm install -g @dynatrace-sdk/dt-app
              fi

              echo "🔧 Activated nix shell for system: ${system}"
              echo "📦 Available packages: ${packageNames}"
              echo "   See https://developer.dynatrace.com/quickstart/tutorial/create-new-dynatrace-app/"
              echo "🚀 Dynatrace App Development Environment"
              echo "   - dt-app CLI available"
              echo "   - Run 'dt-app --help' to get started"
              echo "   - Run 'bootstrap-dynatrace-app' to create a new app"
              echo ""
              echo "💡 Common dt-app commands:"
              echo "   - dt-app dev     : Start development server"
              echo "   - dt-app build   : Build the app"
              echo "   - dt-app deploy  : Deploy the app"
              echo "   - dt-app test    : Run tests"
            '';
          };
        }
      );
    };
}
