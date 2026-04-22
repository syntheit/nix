# Foyer — pre-built binary package
# TODO: replace with buildGoModule when the repo is on GitHub
{ stdenv, ... }:

let
  isLinux = stdenv.hostPlatform.isLinux;
  isDarwin = stdenv.hostPlatform.isDarwin;
  isAarch64 = stdenv.hostPlatform.isAarch64;
in
stdenv.mkDerivation {
  pname = "foyer";
  version = "0.1.0";
  src = ./.;
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/bin
    ${if isLinux && isAarch64 then ''
      cp $src/foyer-bin-arm64 $out/bin/foyer
      chmod +x $out/bin/foyer
    '' else if isLinux then ''
      cp $src/foyer-bin $out/bin/foyer
      chmod +x $out/bin/foyer
    '' else if isDarwin then ''
      cp $src/foyer-api-darwin $out/bin/foyer-api
      chmod +x $out/bin/foyer-api
    '' else ""}
  '';
  meta.platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
}
