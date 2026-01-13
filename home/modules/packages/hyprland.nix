{ pkgs, ... }:

with pkgs; [
  hyprpaper
  hypridle
  hyprpicker
  hyprpolkitagent
  hyprsunset
  grimblast
  pavucontrol
  pamixer
  nwg-displays
  networkmanagerapplet
  eww
  wl-clipboard
  copyq
  (pkgs.callPackage ../../../packages/hyprland-dynamic-borders { })
]
