{
  description = "A Markdown to PDF over LuaLaTeX Converter Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-derivation-hofs = {
      url = "github:metzenseifner/nix-derivation-hofs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-derivation-hofs,
      ...
    }:
    let
      traverseSystems =
        f:
        inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed (
          system: f inputs.nixpkgs.legacyPackages.${system}
        );
      perSystemOutputs =
        system: pkgs:
        let
          letter_template = pkgs.writeTextFile {
            name = "letter_template";
            text = builtins.readFile ./letter_template.lualatex.tex;
          };
          pandoc_preamble = pkgs.writeTextFile {
            name = "pandoc_preamble";
            text = ''
              \providecommand{\tightlist}{%
                \setlength{\itemsep}{0pt}\setlength{\parskip}{0pt}}
              \usepackage{longtable}
              \usepackage{booktabs}
              \usepackage{array}
              \usepackage{calc}
            '';
          };
          inherit (nix-derivation-hofs.lib) withDocs mkHelpPkg;
          scriptFactories = {
            pandoc-texify =
              name:
              withDocs "${name} [FILE]" (
                pkgs.writeShellApplication {
                  name = name;
                  runtimeInputs = [
                    pkgs.pandoc
                    pkgs.gnused
                    pkgs.texlive.combined.scheme-medium
                  ];
                  text = ''
                    set -x
                    if [ $# -lt 1 ]; then
                      echo "usage: ${name} FILE" >&2
                      exit 1
                    fi

                    input_file="''${1:?usage: ${name} FILE}"
                    canonical_file="$(readlink -f "''${input_file}")"
                    parent_dir="$(dirname "''${canonical_file}")"
                    file_name="$(basename "''${canonical_file}")"

                    cd "''${parent_dir}"

                    pandoc -s -i "''${file_name}" \
                      --pdf-engine=lualatex \
                      --template ${letter_template} \
                      --include-in-header=${pandoc_preamble} \
                      --no-highlight \
                      -o "$(printf "%s" "''${file_name}" |  sed 's/\.[^.]*$//').pdf"
                  '';
                }
              );
          };
          resolved = pkgs.lib.mapAttrs (name: f: f name) scriptFactories;
          scripts = resolved // {
            pandoc-texify-help = mkHelpPkg {
              inherit pkgs;
              name = "pandoc-texify-help";
              derivations = builtins.attrValues resolved;
            };
            default = resolved.pandoc-texify;
          };
        in
        # Define outputs based on a per system, per pkgs basis
        {
          packages = scripts;
          apps =
            let
              mkBinApp = drv: bin: {
                type = "app";
                program = "${drv}/bin/${bin}";
              };
            in
            pkgs.lib.mapAttrs (name: drv: mkBinApp drv name) (
              pkgs.lib.filterAttrs (name: _: name != "default") scripts
            );
          devShells.default = pkgs.mkShell {
            packages = [
              scripts.pandoc-texify-help
              scripts.pandoc-texify
            ];
          };
        };
    in
    {
      # Projections over Record(system)
      packages = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).packages);
      apps = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).apps);
      devShells = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).devShells);
      # checks = traverseSystems (pkgs: (perSystemOutputs pkgs.system pkgs).checks);
    };
}
