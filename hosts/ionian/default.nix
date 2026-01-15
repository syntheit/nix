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

  boot.kernelParams = [ "i915.enable_psr=0" ];

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];
}
