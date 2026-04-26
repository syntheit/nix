{ pkgs, ... }:

{
  home.packages = [ pkgs.square-corners ];

  # Dylib injection DISABLED. Tested 2026-04-26:
  #
  # macOS hardened-runtime + library-validation processes (Dock, ControlCenter,
  # Finder, Preview, etc.) reject any inserted dylib at the dyld level *before*
  # the dylib's constructor runs, so a bundle-ID guard inside the dylib cannot
  # save them. dyld then terminates the host process — Dock crashes, Preview
  # fails to open, the system UI breaks. Building the dylib as a fat
  # arm64+arm64e binary fixes the architecture mismatch but does NOT help the
  # library-validation rejection.
  #
  # The only safe way to put this back is per-app injection (LSEnvironment in
  # the app's Info.plist or a launcher wrapper) targeting only unhardened
  # third-party apps like Ghostty/Marta. The global launchctl-setenv approach
  # is not viable on modern macOS.
  launchd.agents.square-corners-dylib = {
    enable = false;
    config = {
      ProgramArguments = [
        "/bin/launchctl"
        "setenv"
        "DYLD_INSERT_LIBRARIES"
        "${pkgs.square-corners}/lib/libsquarecorners.dylib"
      ];
      RunAtLoad = true;
    };
  };

  # Overlay daemon DISABLED. The ears it draws are flat black, which is only
  # invisible against a black desktop. With any other wallpaper they look like
  # added black corner artifacts, not subtle masks. The dylib half is also
  # disabled (see comment above), so neither half of the square-corners
  # feature is currently active. Re-enable manually if you want to experiment.
  launchd.agents.square-corners-overlay = {
    enable = false;
    config = {
      ProgramArguments = [ "${pkgs.square-corners}/bin/square-corners-overlay" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}
