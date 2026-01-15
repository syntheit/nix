{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../system
    ../../services
    ../../desktop
  ];

  networking.hostName = "ionian";

  # Laptop specific settings
  # services.thermald.enable = true;
  # services.tlp.enable = true;
}

