# TODO(mitchellh): This currently doesn't fully work. It generates a binary
# that smashes the stack on run. I'm not sure why.
{ stdenv
, lib
, libGL
, libX11
, libXcursor
, libXi
, libXrandr
, libXxf86vm
, libxcb
, pkg-config
, zig
, git
}:

let
  # These are the libraries that need to be added to the rpath for
  # the binary so that they run properly on NixOS.
  rpathLibs = [
    libGL
  ] ++ lib.optionals stdenv.isLinux [
    libX11
    libXcursor
    libXi
    libXrandr
    libXxf86vm
    libxcb
  ];
in

stdenv.mkDerivation rec {
  pname = "ghostty";
  version = "0.1.0";

  src = ./..;

  nativeBuildInputs = [ git pkg-config zig ];

  buildInputs = rpathLibs ++ [
    # Nothing yet
  ];

  dontConfigure = true;
  dontPatchELF = true;

  # The Zig cache goes into $HOME, so we set this to be writable
  preBuild = ''
    export HOME=$TMPDIR
  '';

  # Build we do nothing except run hooks
  buildPhase = ''
    runHook preBuild
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    export MACH_SDK_PATH=${src}/vendor/mach-sdk
    zig build \
      -Dcpu=baseline \
      -Dversion-string="${version}-nixdev" \
      --prefix $out \
      install

    strip -S $out/bin/ghostty
    patchelf \
      --set-interpreter $(cat $NIX_CC/nix-support/dynamic-linker) \
      --set-rpath "${lib.makeLibraryPath rpathLibs}" \
      $out/bin/ghostty

    runHook postInstall
  '';

  outputs = [ "out" ];

  meta = with lib; {
    homepage = "https://github.com/mitchellh/ghostty";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
  };
}
