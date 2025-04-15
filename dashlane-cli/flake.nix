{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        dashlane = pkgs.callPackage ./dashlane.nix { inherit pkgs; };
      in {
        overlays = final: prev: { dashlane = dashlane; };
        packages.default = dashlane;
      });
}

