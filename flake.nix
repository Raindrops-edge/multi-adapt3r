{
  description = "ghostty";

  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zls-master.url = "github:zigtools/zls/master";

    # We want to stay as up to date as possible but need to be careful
    # that the glibc versions used by our dependencies from Nix are compatible
    # with the system glibc that the user is building for.
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";

    # Used for shell.nix
    flake-compat = { url = github:edolstra/flake-compat; flake = false; };
  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    let
      overlays = [
        # Our repo overlay
        (import ./nix/overlay.nix)

        # Other overlays
        (final: prev: {
          zigpkgs = inputs.zig.packages.${prev.system};

          # Latest version of Tracy
          tracy = inputs.nixpkgs-unstable.legacyPackages.${prev.system}.tracy;

          # Latest version of ZLS
          zls = inputs.zls-master.packages.${prev.system}.zls;
        })
      ];

      # Our supported systems are the same supported systems as the Zig binaries
      systems = builtins.attrNames inputs.zig.packages;
    in flake-utils.lib.eachSystem systems (system:
      let pkgs = import nixpkgs { inherit overlays system; };
      in rec {
        devShell = pkgs.devShell;
        packages.ghostty = pkgs.ghostty;
        defaultPackage = packages.ghostty;
      }
    );
}
