{

  inputs = {
    fenix.url = "https://flakehub.com/f/nix-community/fenix/*";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/*";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
  };

  outputs = inputs@{ flake-parts, ... }:
    # https://flake.parts/module-arguments.html
    flake-parts.lib.mkFlake { inherit inputs; }
    (top@{ config, withSystem, moduleWithSystem, ... }: {
      imports = [ ];
      flake = { };
      systems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      perSystem = { system, pkgs, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [ inputs.fenix.overlays.default ];
          config = { };
        };

        devShells.default = pkgs.mkShell (let
          linuxOnlyPkgs = with pkgs;
            lib.optionals stdenv.isLinux [ gcc13 glibc openssl_3_4 ];
          runtimePkgs = linuxOnlyPkgs;
          rustToolchain = pkgs.fenix.toolchainOf {
            channel = "nightly";
            date = "2025-04-19";
            sha256 = "sha256-0VegWUJe3fqLko+gWT07cPLZs3y0oN1NQA7bKDeDG0I=";
          };
        in {
          packages = with pkgs; [
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
          ];

          buildInputs = runtimePkgs;

          shellHook = ''
            export VENV=$(git rev-parse --show-toplevel)/.venv

            # Set `nix-ld` env vars for nixos users that need these to be able
            # to run `ruff`.
            export NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}
            export NIX_LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath linuxOnlyPkgs}

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

            source $VENV/bin/activate
          '';
        });
      };
    });
}
