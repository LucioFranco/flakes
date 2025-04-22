{

  inputs = {
    fenix.url = "https://flakehub.com/f/nix-community/fenix/*";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/*";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ ... }: {
      imports = [ inputs.git-hooks.flakeModule inputs.treefmt-nix.flakeModule ];
      flake = { };
      systems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      perSystem = { config, system, pkgs, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [ inputs.fenix.overlays.default ];
          config = { };
        };

        formatter = config.treefmt.build.wrapper;
        checks.formatting = config.treefmt.build.check self;

        pre-commit = {
          check.enable = true;
          settings.hooks = {
            actionlint.enable = true;
            shellcheck.enable = true;
            ruff.enable = true;
            treefmt.enable = true;

            polars-clippy = {
              enable = true;
              name = "polars-clippy";
              entry = "make clippy";
            };
          };
        };

        treefmt = let
          rustToolchain = pkgs.fenix.toolchainOf {
            channel = "nightly";
            date = "2025-04-19";
            sha256 = "sha256-0VegWUJe3fqLko+gWT07cPLZs3y0oN1NQA7bKDeDG0I=";
          };
        in {
          projectRootFile = ".git/config";
          flakeCheck = false; # Covered by git-hooks check
          settings.formatter = {
            # Use a custom rustfmt because why not, if this stops working
            # we can just start calling `make fmt`.
            "rustfmt-custom" = {
              command = "${pkgs.bash}/bin/bash";
              options = [
                "-euc"
                ''
                  TARGET_DIR="compute-plane/crates/pc-mpchash"

                  IGNORED_FILES=("control-plane/backend/crates/grpc/src/utils.rs") 

                  is_ignored() {
                    local target="$1"
                    for ignored in $IGNORED_FILES; do
                      [[ "$target" == "$ignored" ]] && return 0
                    done
                    return 1
                  }

                  for file in "$@"; do
                    if is_ignored "$file"; then
                      echo "Skipping ignored file: $file"
                      continue
                    fi

                    if [[ "$file" != "$TARGET_DIR"/* ]]; then
                      "${rustToolchain.rustfmt}/bin/rustfmt" --edition 2024 "$file"
                    else
                      "${rustToolchain.rustfmt}/bin/rustfmt" "$file"
                    fi
                  done 
                ''
                "--" # bash swallows the second argument when using -c
              ];
              includes = [ "*.rs" ];
            };
          };
          programs = {
            nixfmt-classic.enable = true;
            ruff-format.enable = true;
            dprint.enable = true;
          };
        };

        devShells.default = pkgs.mkShell (let
          linuxOnlyPkgs = with pkgs;
            lib.optionals stdenv.isLinux [ gcc13 openssl_3_4 ];
          runtimePkgs = linuxOnlyPkgs;
          rustToolchain = pkgs.fenix.toolchainOf {
            channel = "nightly";
            date = "2025-04-19";
            sha256 = "sha256-0VegWUJe3fqLko+gWT07cPLZs3y0oN1NQA7bKDeDG0I=";
          };
        in {
          packages = with pkgs;
            [
              git
              python311
              nixfmt-classic
              dprint
              uv
              protobuf
              postgresql_16
              sqlx-cli
              cargo-nextest
              bunyan-rs
              bash
              openssl_3_4

              (rustToolchain.withComponents [
                "cargo"
                "clippy"
                "rust-src"
                "rustc"
                "rustfmt"
                "rust-analyzer"
              ])

              config.treefmt.build.wrapper
            ] ++ (lib.attrValues config.treefmt.build.programs);

          buildInputs = runtimePkgs;

          shellHook = ''
            export VENV=$(git rev-parse --show-toplevel)/.venv

            # Set `nix-ld` env vars for nixos users that need these to be able
            # to run `ruff`.
            export NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}
            export NIX_LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath linuxOnlyPkgs}

            # Jemmalloc compiled with gcc doesn't like when we ask for the
            # compiler to compile with fortify source so lets enable everything
            # but fortify and fortify3.
            export NIX_HARDENING_ENABLE="bindnow format pic relro stackclashprotection stackprotector strictoverflow zerocallusedregs"

            # Set openssl for `cargo test` to work.
            export LD_LIBRARY_PATH=${pkgs.openssl_3_4.out}/lib:$LD_LIBRARY_PATH

            export PYO3_NO_REOCOMPILE=1
            export PYO3_NO_RECOMPILE=1

            export PYO3_PYTHON=$($VENV/bin/python -c "import sys,os; print(os.path.abspath(sys.executable))")
            export PYTHON_SHARED_LIB=$($VENV/.venv/bin/python -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))")

            export POLARS_CLOUD_REST_DOMAIN_PREFIX=main.rest.api
            export POLARS_CLOUD_GRPC_DOMAIN_PREFIX=main.grpc.api
            export POLARS_CLOUD_DOMAIN=dev.cloud.pola.rs

            if [ ! -d $VENV ]; then
              uv venv $VENV

              unset CONDA_PREFIX \
                 &&  MATURIN_PEP517_ARGS="--profile dev" uv pip install -r requirements-dev.txt  
            fi

            ${config.pre-commit.installationScript}

            source $VENV/bin/activate
          '';
        });
      };
    });
}
