{ pkgs, ... }:

{
  home.packages = [ pkgs.wallpaper-cycle ];

  # Watch daemon disabled. It detects external wallpaper changes (e.g. via
  # System Settings) and auto-processes them, which fought any attempt to
  # set a custom wallpaper manually. fn+alt+. and fn+alt+, still work because
  # they invoke `wallpaper-cycle next/prev` directly, independent of this
  # background daemon.
  launchd.agents.wallpaper-cycle = {
    enable = false;
    config = {
      ProgramArguments = [ "${pkgs.wallpaper-cycle}/bin/wallpaper-cycle" "watch" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}
