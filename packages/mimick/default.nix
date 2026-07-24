# Mimick — GTK4/libadwaita Immich client. Built from Daniel's mobile fork
# (github.com/syntheit/mimick), which carries the phone-oriented work: touch
# scroll, Immich-style square day-grid, inline video, and the Immich-mobile
# photo viewer. Pinned to a fork commit (push+pin, not a local path).
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
  # gdk-pixbuf loaders for thumbnail decode (see postInstall).
  gnome,
  librsvg,
  webp-pixbuf-loader,
  # minimap widget in the viewer's details drawer.
  libshumate,
  # GStreamer media backend + codecs so gtk::Video streams Immich video inline.
  gst_all_1,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "mimick";
  version = "9.8.0-mobile";

  src = fetchFromGitHub {
    owner = "syntheit";
    repo = "mimick";
    rev = "b90811e";
    hash = "sha256-kgcJEWaRE6t47UVNrIJDfjeGYWPmh45wMpPdmbCbaho=";
  };

  cargoHash = "sha256-nR38JuLnO4e1e0tHUp7qcWtOB+3ty2XLmpqRSY0GO30=";

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
    libshumate # shumate crate — minimap in the details drawer
    # gtk4's media-gstreamer backend needs these plugins in the closure;
    # wrapGAppsHook4 sets GST_PLUGIN_SYSTEM_PATH from them. base/good/bad + libav
    # cover the h264/mp4 Immich serves at /video/playback.
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
    # gtk4paintablesink — renders GStreamer video into a gdk::Paintable shown in
    # a gtk::Picture (the Delfin/Showtime approach). We drive it from a
    # gstplay::Play pipeline in the lightbox rather than gtk::Video, so video
    # playback has real error handling + DMABuf/GL/software fallback for the
    # phone's Adreno GPU. wrapGAppsHook4 adds libgstgtk4.so to the plugin path.
    # The gtk4-only subset produces no gst*.pc, so the stock derivation's
    # `postInstall` (`install ... gst*.pc`) fails with "missing file operand" and
    # its installCheck readelf's the absent webp plugin — neither matters for a
    # runtime-only plugin, so drop both.
    ((gst_all_1.gst-plugins-rs.override { plugins = [ "gtk4" ]; }).overrideAttrs (_: {
      postInstall = "";
      doInstallCheck = false;
    }))
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

    # Thumbnail previews were blank on the phone: Immich serves grid thumbnails
    # as WebP, and mimick's remote-thumbnail path decodes them via gdk-pixbuf
    # (Pixbuf::from_stream_at_scale) — NOT the bundled `webp` crate (that's only
    # the fullscreen lightbox). librsvg (pulled in transitively by gtk4) sets
    # GDK_PIXBUF_MODULE_FILE to its OWN svg-only loaders.cache, which has no webp
    # entry, so every thumbnail failed with "Unrecognized image file format" and
    # the grid rendered blank. Override that var with a COMBINED cache here in
    # postInstall so it's in the env when gappsWrapperArgsHook (preFixup) captures
    # it to wrap the binary. Mirrors nixpkgs eog/zathura. libheif covers local
    # HEIC thumbnails too.
    export GDK_PIXBUF_MODULE_FILE="${
      gnome._gdkPixbufCacheBuilder_DO_NOT_USE {
        extraLoaders = [
          librsvg
          webp-pixbuf-loader
          libheif.lib
        ];
      }
    }"
  '';

  meta = {
    description = "Native GTK4/libadwaita client for Immich (mobile fork)";
    homepage = "https://github.com/syntheit/mimick";
    license = lib.licenses.gpl3Plus;
    mainProgram = "mimick";
    platforms = lib.platforms.linux;
  };
})
