{
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "caps-led-off";
  version = "0.1.0";
  src = ./src;
  nativeBuildInputs = [ swift ];
  buildPhase = "swiftc -O -framework Foundation -framework AppKit -framework IOKit -o caps-led-off $src/main.swift";
  installPhase = "mkdir -p $out/bin; cp caps-led-off $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
