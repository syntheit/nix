{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
    ../../system
    ../../services
    ../../desktop
  ];

  networking.hostName = "caspian";

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };
}
