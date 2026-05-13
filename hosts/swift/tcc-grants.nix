# TCC.db grants for our custom binaries. SIP-off lets us write directly to
# /Library/Application Support/com.apple.TCC/TCC.db. macOS matches the client
# by code-signing requirement; the resolved store path goes in the `client`
# column too. Imported by hosts/swift/default.nix into its activation script.
{ pkgs }:

[
  { service = "kTCCServiceAccessibility";   package = pkgs.yabai;            exec = "yabai";            reason = "yabai window management"; }
  { service = "kTCCServiceAccessibility";   package = pkgs.skhd;             exec = "skhd";             reason = "skhd keybindings"; }
  { service = "kTCCServiceAccessibility";   package = pkgs.menubar-blocker;  exec = "menubar-blocker";  reason = "menubar-blocker CGEventTap"; }
  { service = "kTCCServiceScreenCapture";   package = pkgs.overview;         exec = "overview";         reason = "overview ScreenCaptureKit thumbnails"; }
  { service = "kTCCServiceBluetoothAlways"; package = pkgs.bluetooth-panel;  exec = "bluetooth-panel";  reason = "bluetooth-panel IOBluetooth"; }
  { service = "kTCCServiceLocation";        package = pkgs.wifi-panel;       exec = "wifi-panel";       reason = "wifi-panel CoreWLAN SSID"; }
  { service = "kTCCServiceMicrophone";      package = pkgs.eq;               exec = "eq";               reason = "eq daemon BlackHole input"; }
]
