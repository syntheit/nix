{
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "bluetooth-panel";
  version = "0.1.0";
  src = ./src;
  nativeBuildInputs = [ swift ];
  unpackPhase = "true";
  buildPhase = ''
    swiftc -O \
      -framework AppKit \
      -framework SwiftUI \
      -framework IOBluetooth \
      -framework IOKit \
      -o bluetooth-panel \
      ${../shared}/*.swift $src/*.swift
  '';
  installPhase = "mkdir -p $out/bin; cp bluetooth-panel $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
