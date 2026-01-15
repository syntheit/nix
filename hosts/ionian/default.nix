{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
    ../../system
    ../../services
    ../../desktop
  ];

  networking.hostName = "ionian";

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];
}
