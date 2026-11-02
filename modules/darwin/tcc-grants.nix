# TCC.db grants for our custom binaries. SIP-off lets us write directly to
# /Library/Application Support/com.apple.TCC/TCC.db (modules/darwin/tcc.nix).
# package/exec entries go in by resolved store path; bundleId/requirement
# entries by bundle id and code requirement. Imported by hosts/swift and
# hosts/mini into their activation scripts.
{ pkgs }:

[
  { service = "kTCCServiceAccessibility";   package = pkgs.yabai;            exec = "yabai";            reason = "yabai window management"; }
  { service = "kTCCServiceAccessibility";   package = pkgs.skhd;             exec = "skhd";             reason = "skhd keybindings"; }
  { service = "kTCCServiceAccessibility";   package = pkgs.menubar-blocker;  exec = "menubar-blocker";  reason = "menubar-blocker CGEventTap"; }
  { service = "kTCCServiceListenEvent";     package = pkgs.menubar-blocker;  exec = "menubar-blocker";  reason = "menubar-blocker fn-key flagsChanged tap"; }
  { service = "kTCCServiceListenEvent";     package = pkgs.sketchybar;       exec = "sketchybar";       reason = "sketchybar input monitoring"; }
  { service = "kTCCServiceScreenCapture";   package = pkgs.overview;         exec = "overview";         reason = "overview ScreenCaptureKit thumbnails"; }
  { service = "kTCCServiceMicrophone";      package = pkgs.eq;               exec = "eq";               reason = "eq daemon BlackHole input"; }
  # Telmo.app is the Developer ID signed copy in ~/Applications (home/modules/telmo.nix).
  {
    service = "kTCCServiceBluetoothAlways";
    bundleId = "io.github.syntheit.telmo";
    requirement = ''identifier "io.github.syntheit.telmo" and anchor apple generic and certificate leaf[subject.OU] = "6NHZWHQX37"'';
    reason = "Telmo Bluetooth popup";
  }
]
