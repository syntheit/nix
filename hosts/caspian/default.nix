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

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  system.stateVersion = "25.05";
}
