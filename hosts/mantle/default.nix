{ vars, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
    ../../system
    ../../services
    ../../desktop
  ];

  networking.hostName = "mantle";

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # SSH — Tailscale-only, key-only. trustedInterfaces above lets Tailscale
  # traffic bypass the firewall; openFirewall=false keeps port 22 closed
  # on every other interface (LAN/WAN).
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users."${vars.user.name}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
  ];

  # Passwordless sudo for wheel
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.05";
}
