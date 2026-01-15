{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../system
    ../../services
    ../../desktop
  ];

  networking.hostName = "caspian";
}

