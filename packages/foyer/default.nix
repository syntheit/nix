# Foyer — pre-built binary package
# TODO: replace with buildGoModule when the repo is on GitHub
{ stdenv, ... }:

stdenv.mkDerivation {
  pname = "foyer";
  version = "0.1.0";
  src = ./foyer-bin;
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/foyer
    chmod +x $out/bin/foyer
  '';
  meta.platforms = [ "x86_64-linux" ];
}
