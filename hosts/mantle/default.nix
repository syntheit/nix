{ config, vars, ... }:
{
  imports = [
    ../../modules/numtide-cache.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ../../modules/btrbk-root.nix
    ../../modules/deus-cli.nix
    ./secrets.nix
    ./mac-speakers.nix
    ./brightness.nix
    # ./mdm.nix — MDM stack migrated to vista 2026-08 (hosts/vista/mdm.nix).
    #   /var/lib/mdm state kept here + backup ~/backups/ until retention window ends.
    ../../system
    ../../services
    ../../desktop
  ];

  networking.hostName = "mantle";

  services.tailscale.enable = true;
  # wg0 = the point-to-point link to conduit (hub-and-spoke mesh, mantle =
  # 10.100.0.3). The MDM stack that used to bind here now runs on vista
  # (see the ./mdm.nix note above); conduit keeps mantle as its standby
  # spoke. Trust the interface.
  networking.firewall.trustedInterfaces = [ "tailscale0" "wg0" ];

  # WireGuard tunnel to conduit (VPS gateway).
  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.100.0.3/24" ];
    privateKeyFile = config.sops.secrets.mantle_wg_private_key.path;
    peers = [{
      publicKey = "bhXOmLJsZDR0ZeF/Wnzt116Jw0tHzbfhoe2kG2+ZDAw=";
      endpoint = "192.3.203.146:51820";
      allowedIPs = [ "10.100.0.1/32" ];
      persistentKeepalive = 25;
    }];
  };

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
