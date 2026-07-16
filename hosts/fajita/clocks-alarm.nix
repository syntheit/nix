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
  # Swap bare gnome-clocks for the overridden build that has Oxygen baked in.
  environment.systemPackages = lib.mkAfter [ gnome-clocks-fajita ];
}
