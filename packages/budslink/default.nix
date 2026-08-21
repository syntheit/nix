{
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  gettext,
  desktop-file-utils,
  glib,
  gobject-introspection,
  wrapGAppsHook4,
  gjs,
  gtk4,
  libadwaita,
  libpulseaudio,
  librsvg,
  lib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "budslink";
  version = "0.1.5";

  src = fetchFromGitHub {
    owner = "maniacx";
    repo = "BudsLink";
    rev = "33b61f1a7a3248b24a87b47efb0a57e08992c07b";
    hash = "sha256-zD3WgGjrivzuxwRvlK18jpmCyrQ2WHuSeDo2/JPW/RY=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    gettext
    desktop-file-utils
    glib
    gobject-introspection
    wrapGAppsHook4
  ];

  buildInputs = [
    gjs
    gtk4
    libadwaita
    libpulseaudio
    librsvg
  ];

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix GI_TYPELIB_PATH : "$out/lib/io.github.maniacx.BudsLink/girepository-1.0"
    )
  '';

  meta = {
    description = "Control and monitor supported Bluetooth earbuds";
    homepage = "https://github.com/maniacx/BudsLink";
    license = lib.licenses.gpl3Plus;
    mainProgram = "budslink";
    platforms = lib.platforms.linux;
  };
})
