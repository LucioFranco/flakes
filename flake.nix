{
  description =
    "Ready-made templates for easily creating flake-driven environments";
  inputs.flake-utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.*";
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2411.*";

  outputs = { flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        forEachDir = exec: ''
          for dir in */; do
          (
              cd "''${dir}"

              ${exec}
          )
          done
        '';
      in {
        devShells.default =
          pkgs.mkShell { packages = with pkgs; [ nixd nixfmt ]; };
      });
}
