# gnome-mobile-torch — a GNOME Shell Quick Settings toggle for the phone's flash
# LED(s). Auto-discovers `*:flash` / `*:torch` LEDs and toggles them via logind's
# SetBrightness (no udev rule / root needed — the LED's `:seat:` tag suffices).
# On fajita this drives /sys/class/leds/white:flash (rear) + yellow:flash.
# Not in nixpkgs, so vendored. UUID: torch@vixalien.com.
{
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "gnome-mobile-torch";
  version = "0-unstable-f9cdd40";

  src = fetchFromGitHub {
    owner = "vixalien";
    repo = "gnome-mobile-torch";
    rev = "f9cdd40012d3fd19bd09eb6df0128c2712c4d693";
    hash = "sha256-levQq3M7fJUM6y5nsfsKQpA8o1r7RWmw0V7Dg7QGFPY=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    uuid="torch@vixalien.com"
    dest="$out/share/gnome-shell/extensions/$uuid"
    mkdir -p "$dest"
    cp -r metadata.json extension.js src data "$dest/"
    runHook postInstall
  '';

  meta = {
    description = "GNOME Shell torch/flashlight Quick Settings toggle (mobile)";
    homepage = "https://github.com/vixalien/gnome-mobile-torch";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
