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
        checks.formatting = config.treefmt.build.check;

        pre-commit = {
          check.enable = true;
          settings.hooks = {
            actionlint.enable = true;
            shellcheck.enable = false;
            ruff.enable = true;
            treefmt.enable = true;
            typos.enable = true;

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
          cargo-clean-all = pkgs.rustPlatform.buildRustPackage (let
            rustSrc = pkgs.fetchFromGitHub {
              owner = "dnlmlr";
              repo = "cargo-clean-all";
              rev = "70610d5afa0e11200ef96d23ea642eb05c98282e";
              sha256 = "sha256-kSFshEoys0MjON3I70xPb7VEwmK4ne0ZsaLwpRZfhD0=";
            };
          in {
            name = "cargo-clean-all";
            src = rustSrc;
            cargoLock.lockFile = "${rustSrc}/Cargo.lock";
          });
        in {
          packages = with pkgs;
            [
              git
              python311
              dprint
              uv
              protobuf
              postgresql_16
              sqlx-cli
              cargo-nextest
              bunyan-rs
              bash
              openssl_3_4
              pyright
              cargo-clean-all
              gdb

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

          shellHook = let
            # on macOS and Linux, use faster parallel linkers that are much more
            # efficient than the defaults. these noticeably improve link time even for
            # medium sized rust projects like jj
            rustLinkerFlags = if pkgs.stdenv.isLinux then [
              "-fuse-ld=mold"
              "-Wl,--compress-debug-sections=zstd"
            ] else if pkgs.stdenv.isDarwin then
            # on darwin, /usr/bin/ld actually looks at the environment variable
            # $DEVELOPER_DIR, which is set by the nix stdenv, and if set,
            # automatically uses it to route the `ld` invocation to the binary
            # within. in the devShell though, that isn't what we want; it's
            # functional, but Xcode's linker as of ~v15 (not yet open source)
            # is ultra-fast and very shiny; it is enabled via -ld_new, and on by
            # default as of v16+
            [
              "--ld-path=$(unset DEVELOPER_DIR; /usr/bin/xcrun --find ld)"
              "-ld_new"
            ] else
              [ ];

            rustLinkFlagsString = pkgs.lib.concatStringsSep " "
              (pkgs.lib.concatMap (x: [ "-C" "link-arg=${x}" ])
                rustLinkerFlags);
          in ''
            # export WORKSPACE_ROOT=$(jj workspace root)
            export WORKSPACE_ROOT=$(git rev-parse --show-toplevel)
            export VENV=$WORKSPACE_ROOT/.venv

            if [ ! -d $VENV ]; then
              uv venv $VENV

              unset CONDA_PREFIX \
                 &&  MATURIN_PEP517_ARGS="--profile dev" uv pip install -r requirements-dev.txt  
            fi

            # Jemmalloc compiled with gcc doesn't like when we ask for the
            # compiler to compile with fortify source so lets enable everything
            # but fortify and fortify3.
            export NIX_HARDENING_ENABLE="bindnow format pic relro stackclashprotection stackprotector strictoverflow zerocallusedregs"

            export PYO3_NO_REOCOMPILE=1
            export PYO3_NO_RECOMPILE=1

            export PYO3_PYTHON=$($VENV/bin/python -c "import sys,os; print(os.path.abspath(sys.executable))")
            export PYTHON_SHARED_LIB=$($VENV/bin/python -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))")
            # export PYTHON_SHARED_LIB="$VENV/lib"

            # Set `nix-ld` env vars for nixos users that need these to be able
            # to run `ruff`.
            export NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}
            export NIX_LD_LIBRARY_PATH="${
              pkgs.lib.makeLibraryPath linuxOnlyPkgs
            }:$PYTHON_SHARED_LIB"
            # Set openssl for `cargo test` to work.
            export LD_LIBRARY_PATH="${pkgs.openssl_3_4.out}/lib:$PYTHON_SHARED_LIB"


            export POLARS_CLOUD_REST_DOMAIN_PREFIX=main.rest.api
            export POLARS_CLOUD_GRPC_DOMAIN_PREFIX=main.grpc.api
            export POLARS_CLOUD_DOMAIN=dev.cloud.pola.rs

            ${config.pre-commit.installationScript}

            export RUSTFLAGS="-Zthreads=0 ${rustLinkFlagsString}"

            export PYTHON_LIBS=$($VENV/bin/python -c "import site; print(site.getsitepackages()[0])")

            source $VENV/bin/activate

            export PYTHONPATH="$PYTHONPATH:$VENV/lib/python3.11/site-packages"
          '';
        });
      };
    });
}
