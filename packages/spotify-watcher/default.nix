{
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "spotify-watcher";
  version = "0.1.0";
  src = ./src;
  nativeBuildInputs = [ swift ];
  buildPhase = "swiftc -O -framework Foundation -framework AppKit -o spotify-watcher $src/main.swift";
  installPhase = "mkdir -p $out/bin; cp spotify-watcher $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
