{ pkgs, inputs, ... }:

with pkgs; [
  tor-browser
  brave
  inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
  signal-desktop
  telegram-desktop
  nextcloud-client
  virt-manager
  papirus-icon-theme
  popsicle
  cloudflared
  prismlauncher
  lshw-gui
  parted
  gptfdisk
  cpupower-gui
  jre8
  gvfs
  nemo
  nautilus
  # GNOME applications
  mission-center
  resources
  gnome-2048
  gnome-calculator
]
