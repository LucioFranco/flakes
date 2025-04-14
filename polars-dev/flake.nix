# This flake was initially generated by fh, the CLI for FlakeHub (version 0.1.22)
{

  inputs = {
    fenix.url = "https://flakehub.com/f/nix-community/fenix/*";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/*";
    flake-schemas.url =
      "https://flakehub.com/f/DeterminateSystems/flake-schemas/*";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
  };

  # Flake outputs that other flakes can use
  outputs = { flake-schemas, nixpkgs, fenix, ... }:
    let
      # Helpers for producing system-specific outputs
      supportedSystems = [ "x86_64-linux" "aarch64-darwin" ];
      overlays = [ fenix.overlays.default ];
      # fenix2 = fenix.packages."x86_64-linux";
      forEachSupportedSystem = f:
        nixpkgs.lib.genAttrs supportedSystems
        (system: f { pkgs = import nixpkgs { inherit system overlays; }; });
    in {
      # Schemas tell Nix about the structure of your flake's outputs
      schemas = flake-schemas.schemas;

      # Development environments
      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          # Pinned packages available in the environment
          packages = with pkgs; [
            python311
            nixfmt-classic
            dprint
            uv
            protobuf
            openssl_3_4

            (pkgs.fenix.complete.withComponents [
              "cargo"
              "clippy"
              "rust-src"
              "rustc"
              "rustfmt"
            ])
            rust-analyzer
          ];

          shellHook = ''
            export VENV=$(git rev-parse --show-toplevel)/.venv

            export LD_LIBRARY_PATH=${pkgs.openssl_3_4.out}/lib:$LD_LIBRARY_PATH

            export PYO3_NO_REOCOMPILE=1
            export PYO3_NO_RECOMPILE=1

            export PYO3_PYTHON=$($VENV/bin/python -c "import sys,os; print(os.path.abspath(sys.executable))")
            export PYTHON_SHARED_LIB=$($VENV/.venv/bin/python -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))")

            export POLARS_CLOUD_REST_DOMAIN_PREFIX=main.rest.api
            export POLARS_CLOUD_GRPC_DOMAIN_PREFIX=main.grpc.api
            export POLARS_CLOUD_DOMAIN=dev.cloud.pola.rs

            # uv venv $VENV

            # unset CONDA_PREFIX \
            #   &&  MATURIN_PEP517_ARGS="--profile dev" uv pip install -r requirements-dev.txt

            source $VENV/bin/activate
          '';
        };
      });
    };
}
