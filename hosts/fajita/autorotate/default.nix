# Auto-rotate daemon — claims the accelerometer and applies the matching
# monitor transform via DisplayConfig. Replaces gsd-orientation, which GNOME 49
# dropped. Reads the standard orientation-lock gsetting (from gsd-mobile) so the
# quick-settings Auto Rotate toggle controls it. See autorotate.py.
{
  python3,
  glib,
  gnome-settings-daemon-mobile,
  writeShellApplication,
}:
let
  pyEnv = python3.withPackages (ps: [ ps.pygobject3 ]);
  # gsd-mobile ships org.gnome.settings-daemon.peripherals.touchscreen
  # (orientation-lock); the daemon needs it on its schema path.
  schemas = "${gnome-settings-daemon-mobile}/share/gsettings-schemas/${gnome-settings-daemon-mobile.name}/glib-2.0/schemas";
in
writeShellApplication {
  name = "fajita-autorotate";
  text = ''
    export GI_TYPELIB_PATH=${glib.out}/lib/girepository-1.0
    export GSETTINGS_SCHEMA_DIR=${schemas}
    exec ${pyEnv.interpreter} ${./autorotate.py}
  '';
}
