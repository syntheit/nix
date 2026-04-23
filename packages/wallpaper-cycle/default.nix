{
  stdenv,
}:

stdenv.mkDerivation {
  pname = "wallpaper-cycle";
  version = "0.1.0";
  src = ./src;
  unpackPhase = "true";
  buildPhase = ''
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    export PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH
    swiftc -O \
      -sdk $SDKROOT \
      -framework AppKit \
      -framework AVFoundation \
      -framework CoreGraphics \
      -framework CoreMedia \
      -framework ImageIO \
      -framework UniformTypeIdentifiers \
      -o wallpaper-cycle \
      $src/*.swift
  '';
  installPhase = "mkdir -p $out/bin; cp wallpaper-cycle $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
