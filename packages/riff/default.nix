# Riff — maintained fork of spot (GNOME Spotify client, GTK4/libadwaita).
# spot is officially unmaintained and its bundled librespot 0.6.0 was broken
# by Spotify's 2025 API changes ("Track should be available, but no
# alternatives found"); riff bundles librespot 0.8.0, which works. Not in
# nixpkgs (Flathub only) — derivation mirrors nixpkgs' spot package.nix.
{
  lib,
  stdenv,
  alsa-lib,
  appstream-glib,
  blueprint-compiler,
  cargo,
  desktop-file-utils,
  fetchFromGitHub,
  gettext,
  glib,
  gst_all_1,
  gtk4,
  libadwaita,
  libpulseaudio,
  meson,
  ninja,
  openssl,
  pkg-config,
  rustPlatform,
  rustc,
  wrapGAppsHook4,
}:

stdenv.mkDerivation rec {
  pname = "riff";
  version = "25.11";

  src = fetchFromGitHub {
    owner = "Diegovsky";
    repo = "riff";
    tag = "v${version}";
    sha256 = "1kgpvv05bfvfr5cz4pipkzrz1qc12kjbppvjawvhv748f5fxk4wg";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit pname version src;
    hash = lib.fakeHash;
  };

  # Same as spot: with CARGO_BUILD_TARGET set, cargo puts the binary under a
  # target-triple subdir that meson's copy step doesn't expect.
  postPatch = ''
    substituteInPlace src/meson.build --replace-fail \
      "cargo_output = 'src' / rust_target / meson.project_name()" \
      "cargo_output = 'src' / '${stdenv.hostPlatform.rust.cargoShortTarget}' / rust_target / meson.project_name()"
  '';

  nativeBuildInputs = [
    appstream-glib
    blueprint-compiler
    cargo
    desktop-file-utils
    gettext
    glib # for glib-compile-schemas
    gtk4 # for gtk-update-icon-cache
    meson
    ninja
    pkg-config
    rustPlatform.cargoSetupHook
    rustc
    wrapGAppsHook4
  ];

  buildInputs = [
    alsa-lib
    glib
    gst_all_1.gst-plugins-base
    gst_all_1.gstreamer
    gtk4
    libadwaita
    libpulseaudio
    openssl
  ];

  mesonBuildType = "release";

  env.CARGO_BUILD_TARGET = stdenv.hostPlatform.rust.rustcTargetSpec;

  meta = {
    description = "Native Spotify client for GNOME (maintained fork of spot)";
    homepage = "https://github.com/Diegovsky/riff";
    license = lib.licenses.mit;
    mainProgram = "riff";
    platforms = lib.platforms.linux;
  };
}
