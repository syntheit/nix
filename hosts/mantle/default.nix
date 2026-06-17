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

  # Auto-IP the cdc_ncm USB link to fajita. Phone-side gadget uses a fixed
  # locally-administered MAC (`02:22:82:ff:ff:22` for the mantle-facing end);
  # match on it so the assigned 172.16.42.2/24 sticks regardless of which USB
  # port the cable is in. Use `ssh fajita.usb` for fast closure copy over USB.
  networking.networkmanager.ensureProfiles.profiles.fajita-usb = {
    connection = {
      id = "fajita-usb";
      type = "ethernet";
      autoconnect = true;
      autoconnect-priority = 50;
    };
    "802-3-ethernet".mac-address = "02:22:82:ff:ff:22";
    ipv4 = {
      method = "manual";
      addresses = "172.16.42.2/24";
    };
    ipv6.method = "ignore";
  };
  networking.hosts."172.16.42.1" = [ "fajita.usb" ];

  system.stateVersion = "25.05";
}
