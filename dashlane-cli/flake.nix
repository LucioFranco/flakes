{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; }
    (top@{ config, withSystem, moduelWithSystem, ... }: {
      systems = [ "x86_64-linux" ];

      imports = [ inputs.flake-parts.flakeModules.easyOverlay ];

      perSystem = { config, pkgs, ... }: {
        overlayAttrs = { inherit (config.packages) dashlane-cli; };
        packages.dashlane-cli =
          pkgs.callPackage ./dashlane.nix { inherit pkgs; };
      };
    });
}

