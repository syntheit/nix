{
  stdenv,
}:

stdenv.mkDerivation {
  pname = "corner-mask";
  version = "0.1.0";
  src = ./src;
  unpackPhase = "true";
  buildPhase = ''
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    export PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH
    swiftc -O \
      -sdk $SDKROOT \
      -framework AppKit \
      -framework SwiftUI \
      -o corner-mask \
      $src/*.swift
  '';
  installPhase = "mkdir -p $out/bin; cp corner-mask $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
