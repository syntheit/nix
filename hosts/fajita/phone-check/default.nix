# Phone Check — libadwaita diagnostic app for fajita (sensors + keyring re-key).
{
  stdenvNoCC,
  python3,
  gtk4,
  libadwaita,
  glib,
  pango,
  gdk-pixbuf,
  graphene,
  harfbuzz,
  gobject-introspection,
  wrapGAppsHook4,
  makeDesktopItem,
  lib,
}:
let
  pyEnv = python3.withPackages (ps: [ ps.pygobject3 ]);

  # The typelib chain libadwaita pulls in at runtime.
  typelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    gtk4
    libadwaita
    glib
    pango
    gdk-pixbuf
    graphene
    harfbuzz
    gobject-introspection
  ];

  desktopItem = makeDesktopItem {
    name = "io.matv.PhoneCheck";
    desktopName = "Phone Check";
    comment = "Sensor + keyring diagnostics";
    exec = "phone-check";
    icon = "utilities-system-monitor";
    categories = [ "Utility" "System" ];
    startupWMClass = "io.matv.PhoneCheck";
  };
in
stdenvNoCC.mkDerivation {
  pname = "phone-check";
  version = "1.0";
  dontUnpack = true;

  nativeBuildInputs = [ wrapGAppsHook4 gobject-introspection ];
  buildInputs = [ gtk4 libadwaita ];

  installPhase = ''
    runHook preInstall
    install -Dm755 /dev/stdin $out/bin/phone-check <<EOF
    #!${pyEnv.interpreter}
    import os
    os.environ.setdefault("GI_TYPELIB_PATH", "${typelibPath}")
    exec(open("${./phone_check.py}").read())
    EOF
    cp -r ${desktopItem}/share $out/share
    runHook postInstall
  '';

  # wrapGAppsHook4 prepends GI_TYPELIB_PATH / GSETTINGS_SCHEMA_DIR for the
  # bin/ launcher automatically during fixup.
}
