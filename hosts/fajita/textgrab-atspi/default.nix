# fajita-textgrab-atspi — AT-SPI backend for the shell's long-press text-grab
# ("long-press -> read text -> Copy").
#
# Runtime wiring notes:
#   * GI_TYPELIB_PATH must carry the Atspi typelib (from at-spi2-core) AND the
#     GLib/Gio typelibs (from glib) so pygobject can resolve the `Atspi` and
#     `GLib` namespaces used by textgrab_atspi.py.
#   * PYTHONPATH must carry the gi Atspi override module (the .py shipped by
#     at-spi2-core under lib/${python3.libPrefix}/site-packages/gi/overrides).
#   * The a11y bus must be running: GTK apps register on the session a11y bus
#     by default, so the shell/session must have accessibility enabled for the
#     desktop/app tree to be visible over AT-SPI.
{
  python3,
  at-spi2-core,
  glib,
  gobject-introspection,
  writeShellApplication,
}:
let
  pyEnv = python3.withPackages (ps: [ ps.pygobject3 ]);
in
writeShellApplication {
  name = "fajita-textgrab-atspi";
  text = ''
    # Atspi typelib from at-spi2-core; GLib/Gio from glib; DBus-1.0 (Atspi's GIR includes it) from gobject-introspection.
    export GI_TYPELIB_PATH=${at-spi2-core}/lib/girepository-1.0:${glib.out}/lib/girepository-1.0:${gobject-introspection}/lib/girepository-1.0
    # pygobject finds the typelib via GI_TYPELIB_PATH, but the gi Atspi override
    # (.py) must be on PYTHONPATH. python3.libPrefix resolves to e.g. python3.13.
    export PYTHONPATH=${at-spi2-core}/lib/${python3.libPrefix}/site-packages''${PYTHONPATH:+:}''${PYTHONPATH:-}
    exec ${pyEnv.interpreter} ${./textgrab_atspi.py} "$@"
  '';
}
