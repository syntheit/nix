{ pkgs, ... }:

{
  # square-corners ships a dylib only — the overlay daemon was removed once
  # the dylib's _cornerMask swizzle started returning a square NSImage (the
  # piece the 2026-04 build missed). With that fix the dylib alone makes
  # both top and bottom corners truly sharp, so the black-triangle overlay
  # is no longer needed.
  #
  # Persistent global injection via `launchctl setenv DYLD_INSERT_LIBRARIES`
  # is NOT viable on modern macOS: hardened-runtime + library-validation
  # processes (Dock, ControlCenter, Finder, Preview) reject any inserted
  # dylib at dyld level before the bundle-ID guard runs, and dyld then
  # terminates the host. Per-app injection (LSEnvironment in the target
  # app's Info.plist, or a launcher wrapper) is the only safe path —
  # configured separately per app, not in this module.
  #
  # Quick manual test:
  #   DYLD_INSERT_LIBRARIES=${pkgs.square-corners}/lib/libsquarecorners.dylib \
  #     /Applications/Ghostty.app/Contents/MacOS/ghostty
  home.packages = [ pkgs.square-corners ];
}
