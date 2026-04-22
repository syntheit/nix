{
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "dashboard";
  version = "0.1.0";
  src = ./src;
  nativeBuildInputs = [ swift ];
  unpackPhase = "true";
  buildPhase = ''
    swiftc -O \
      -framework AppKit \
      -framework SwiftUI \
      -framework IOKit \
      -framework EventKit \
      -framework CoreAudio \
      -o dashboard \
      $src/*.swift
  '';
  installPhase = "mkdir -p $out/bin; cp dashboard $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
