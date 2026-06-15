{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  wayland-scanner,
  qt6,
  wayland,
  libxkbcommon,
  libei,
}:
# RemoteDesktop xdg-desktop-portal backend that bridges KDE Connect's remote
# input (mouse/keyboard) to wlroots-style compositors (Hyprland) via the
# virtual-pointer / virtual-keyboard protocols. Not in nixpkgs — built from
# github:iamnarayana/wayland-kdeconnect-fix (the "hypr-kdeconnect-fix" the
# Hyprland wiki points at). Ships its own .portal, D-Bus service, and systemd
# user unit; wired up in hosts/vista/default.nix.
stdenv.mkDerivation {
  pname = "hypr-kdeconnect-fix";
  version = "0-unstable-2026-05-06";

  src = fetchFromGitHub {
    owner = "iamnarayana";
    repo = "wayland-kdeconnect-fix";
    rev = "ea55f66c8238235983d60d381bf2abe1fed50043";
    hash = "sha256-OW18+pO92XvlTLrHo+S9/EVUophr5Dl1GdGJcmVAq/o=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    wayland-scanner
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    wayland
    libxkbcommon
    libei
  ];

  cmakeFlags = [ "-DBUILD_TESTING=OFF" ];

  meta = {
    description = "RemoteDesktop portal backend for KDE Connect remote input on wlroots/Hyprland";
    homepage = "https://github.com/iamnarayana/wayland-kdeconnect-fix";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "hypr-kdeconnect-portal";
  };
}
