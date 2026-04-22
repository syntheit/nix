{
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "volume-panel";
  version = "0.1.0";
  src = ./src;
  nativeBuildInputs = [ swift ];
  unpackPhase = "true";
  buildPhase = ''
    swiftc -O \
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
