{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
    ../../system
    ../../services
    ../../desktop
  ];

  networking.hostName = "caspian";
}
