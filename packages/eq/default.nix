{
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "eq";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = "swiftc -O -framework AVFAudio -framework CoreAudio -framework AudioToolbox -o eq $src/eq.swift";
  installPhase = "mkdir -p $out/bin; cp eq $out/bin/";
  meta.platforms = [ "aarch64-darwin" ];
}
