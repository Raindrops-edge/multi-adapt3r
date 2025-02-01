final: prev: rec {
  # Notes:
  #
  # When determining a SHA256, use this to set a fake one until we know
  # the real value:
  #
  #    vendorSha256 = nixpkgs.lib.fakeSha256;
  #

  devShell = prev.callPackage ./devshell.nix { };
  ghostty = prev.callPackage ./package.nix { };

  wraptest = prev.callPackage ./wraptest.nix { };

  # Last known working self-hosted with -fstage1, due to
  # https://github.com/ziglang/zig/issues/12944
  # I ended up finding a workaround for this but I still feel
  # weird about it so I'm going to keep this around in case
  # we want to rollback.
  #zig = final.zigpkgs.master-2022-09-13;

  # zig we want to be the latest nightly since 0.9.0 is not released yet.
  zig = final.zigpkgs.master;

  # last known working stage1 build, the rest in the future are stage3
  #zig = final.zigpkgs.master-2022-08-19;
}
