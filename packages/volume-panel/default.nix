{
  stdenv,
}:

stdenv.mkDerivation {
  pname = "volume-panel";
  version = "0.1.0";
  src = ./src;
  unpackPhase = "true";
  buildPhase = ''
    # Use system Swift compiler with macOS 26 SDK for liquid glass APIs
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    export PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH
    swiftc -O \
      -sdk $SDKROOT \
      -framework AppKit \
      -framework SwiftUI \
      -framework CoreAudio \
      -framework AudioToolbox \
      -o volume-panel \
      ${../shared}/*.swift $src/*.swift
  '';
  installPhase = "mkdir -p $out/bin; cp volume-panel $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
