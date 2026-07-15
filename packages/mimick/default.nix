# Mimick — GTK4/libadwaita Immich client (github.com/nicx17/mimick).
# Verified build: v9.8.0 on x86_64-linux.
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  glib,
  cmake,
  nasm,
  gtk4,
  libadwaita,
  openssl,
  libheif,
  libraw,
  openjpeg,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "mimick";
  version = "9.8.0";

  src = fetchFromGitHub {
    owner = "nicx17";
    repo = "mimick";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Yg+1d/bOSWLzdzwKKmhMkjhgvgG+vffMp9kJrCsDyEY=";
  };

  cargoHash = "sha256-/AdHErZTVbvZtg4u9CURgR78naglzAx9ZdB2HePdr6U=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
    glib # glib-compile-resources for build.rs
    cmake # turbojpeg "cmake" feature
    rustPlatform.bindgenHook # libheif-rs / libraw-rs-sys use bindgen
  ]
  # nasm is x86-only (turbojpeg-sys SIMD asm); aarch64 (the phone) falls back to
  # turbojpeg's C paths, so only pull nasm in on x86.
  ++ lib.optional stdenv.hostPlatform.isx86_64 nasm;

  buildInputs = [
    gtk4
    libadwaita
    glib
    openssl # reqwest native-tls
    libheif # libheif-rs v1_20
    libraw # libraw-rs-sys
    openjpeg # jpeg2k / openjpeg-sys
  ];

  postInstall = ''
    install -Dm644 setup/dev.nicx.mimick.desktop \
      $out/share/applications/dev.nicx.mimick.desktop
    install -Dm644 setup/metainfo/dev.nicx.mimick.metainfo.xml \
      $out/share/metainfo/dev.nicx.mimick.metainfo.xml
    install -Dm644 src/assets/scalable/apps/dev.nicx.mimick.svg \
      $out/share/icons/hicolor/scalable/apps/dev.nicx.mimick.svg
    install -Dm644 src/assets/256x256/apps/dev.nicx.mimick.png \
      $out/share/icons/hicolor/256x256/apps/dev.nicx.mimick.png
    install -Dm644 src/assets/512x512/apps/dev.nicx.mimick.png \
      $out/share/icons/hicolor/512x512/apps/dev.nicx.mimick.png
  '';

  meta = {
    description = "Native GTK4/libadwaita client for Immich (mobile-adaptive)";
    homepage = "https://github.com/nicx17/mimick";
    license = lib.licenses.gpl3Plus;
    mainProgram = "mimick";
    platforms = lib.platforms.linux;
  };
})
