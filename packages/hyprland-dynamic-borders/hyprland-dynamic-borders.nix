{ lib, stdenv, fetchFromGitHub, makeWrapper, socat, jq }:
stdenv.mkDerivation rec {
  name = "hyprland-dynamic-borders-${version}";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "devadathanmb";
    repo = "hyprland-smart-borders";
    rev = "d57b24c5aedaf5c06f01063a7f609d013d88c990";
    sha256 = "RI5QV1S83GUm7jyQvd3Bm0RfIQbO8MfVN6HgYDU+YkU=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ ];

  installPhase = ''
    mkdir -p $out/bin
    cp dynamic-borders.sh $out/bin/hyprland-dynamic-borders
    wrapProgram $out/bin/hyprland-dynamic-borders \
      --prefix PATH : ${lib.makeBinPath [ socat jq ]}
  '';
}

