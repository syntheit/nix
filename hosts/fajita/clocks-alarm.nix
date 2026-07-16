{ pkgs, lib, ... }:
let
  # AOSP "Oxygen" alarm tone — pleasant marimba-style rising tone,
  # Apache 2.0 licensed (AOSP platform/frameworks/base).
  # Source: https://android.googlesource.com/platform/frameworks/base
  #         data/sounds/alarms/ogg/Oxygen.ogg
  customAlarm = ./sounds/alarm-clock-elapsed.oga;

  gnome-clocks-fajita = pkgs.gnome-clocks.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      cp ${customAlarm} data/sounds/alarm-clock-elapsed.oga
    '';
  });
in
{
  # services.desktopManager.gnome.core-apps (enabled by default) pulls in the
  # stock pkgs.gnome-clocks via removeExcluded. Without excluding it here, both
  # the stock and the overridden build land in the system closure with identical
  # D-Bus service names and .desktop files. The symlink collision in
  # /run/current-system/sw/share/dbus-1/services/ causes D-Bus activation to
  # pick whichever wins the profile merge — in practice the stock one, so
  # gnome-clocks launched from the app drawer always plays the default beep.
  #
  # Excluding pkgs.gnome-clocks by name removes the stock package from the
  # GNOME core-apps list (removeExcluded matches by pname). Only the override
  # below is then present in the closure, so activation unambiguously picks it.
  environment.gnome.excludePackages = [ pkgs.gnome-clocks ];

  # Install our override (Oxygen baked in) as the sole gnome-clocks.
  environment.systemPackages = [ gnome-clocks-fajita ];
}
