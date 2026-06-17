{
  lib,
  stdenv,
  fetchFromGitLab,
  pkg-config,
  dbus,
  tinyalsa,
}:

stdenv.mkDerivation {
  pname = "q6voiced";
  version = "0-unstable-2026-06-14";

  src = fetchFromGitLab {
    owner = "postmarketOS";
    repo = "q6voiced";
    rev = "75ae4079fc40c1c555ce9129ee86780bf598aaf6";
    sha256 = "0lprz28d141bk096g9gnjlf7jz494lq1cxppwswyqr29ch3qlczg";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    dbus
    tinyalsa
  ];

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -o q6voiced q6voiced.c \
      $(pkg-config --cflags --libs dbus-1) \
      -ltinyalsa
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 q6voiced $out/bin/q6voiced
    runHook postInstall
  '';

  meta = {
    description = "Userspace daemon for the QDSP6 voice call audio driver (sdm845/msm8916)";
    homepage = "https://gitlab.com/postmarketOS/q6voiced";
    license = lib.licenses.mit;
    mainProgram = "q6voiced";
    platforms = lib.platforms.linux;
  };
}
