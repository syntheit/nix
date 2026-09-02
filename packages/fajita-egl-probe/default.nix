{
  stdenv,
  libGL,
  libgbm,
  libdrm,
  pkg-config,
  lib,
}:

stdenv.mkDerivation {
  pname = "fajita-egl-probe";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    libGL
    libgbm
    libdrm
  ];

  buildPhase = ''
    runHook preBuild
    ''${CC:-cc} probe.c -o fajita-egl-probe -std=c11 -O2 -Wall \
      $(pkg-config --cflags --libs egl glesv2 gbm libdrm)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp fajita-egl-probe $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "Read-only surfaceless-EGL + dma-buf import probe for the Adreno 630 (libcamera GPU debayer feasibility)";
    platforms = lib.platforms.linux;
  };
}
