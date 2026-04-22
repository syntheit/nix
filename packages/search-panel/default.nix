{
  stdenv,
}:

stdenv.mkDerivation {
  pname = "search-panel";
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
      -o search-panel \
      ${../shared}/*.swift $src/*.swift
  '';
  installPhase = "mkdir -p $out/bin; cp search-panel $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
