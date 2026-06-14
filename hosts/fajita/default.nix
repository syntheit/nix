{
  config,
  lib,
  pkgs,
  ...
}:
{
  networking.hostName = "fajita";

  # Phosh shell — upstream NixOS module; mobile-nixos's example imports this verbatim
  services.xserver.desktopManager.phosh = {
    enable = true;
    user = "daniel";
    group = "users";
  };
  programs.calls.enable = true;
  hardware.sensor.iio.enable = true;

  # Silent boot + splash so the phone looks like a phone, not a server
  mobile.beautification = {
    silentBoot = lib.mkDefault true;
    splash = lib.mkDefault true;
  };

  # Networking — iwd backend for NetworkManager (matches pmOS choice)
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  users.users.daniel = {
    isNormalUser = true;
    description = "Daniel";
    initialPassword = "1234";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "dialout"
      "feedbackd"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    epiphany
    gnome-console
    megapixels
    vim
    htop
    git
    curl
  ];

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Argentina/Buenos_Aires";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "26.05";
}
