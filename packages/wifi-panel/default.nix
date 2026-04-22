{
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "wifi-panel";
  version = "0.1.0";
  src = ./src;
  nativeBuildInputs = [ swift ];
  unpackPhase = "true";
  buildPhase = ''
    swiftc -O \
      -framework AppKit \
      -framework SwiftUI \
      -framework CoreWLAN \
      -framework CoreImage \
      -framework SystemConfiguration \
      -o wifi-panel \
      ${../shared}/*.swift $src/*.swift
  '';
  installPhase = "mkdir -p $out/bin; cp wifi-panel $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
