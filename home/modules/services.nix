{ ... }:

{
  services.swaync = {
    enable = true;
  };

  # Enable gnome-keyring for storing WiFi passwords and other secrets
  # NetworkManager uses the secret service component to store WiFi passwords
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" "ssh" "pkcs11" ];
  };

  # Ensure gnome-keyring starts early so NetworkManager can access WiFi passwords
  # Start before graphical-session.target so it's available when NetworkManager tries to connect
  # NetworkManager (system service) communicates with the user's gnome-keyring via D-Bus
  systemd.user.services.gnome-keyring = {
    Unit = {
      # Start early, before NetworkManager needs it
      After = [ "dbus.service" ];
      Wants = [ "dbus.service" ];
      # Start gnome-keyring before graphical session so NetworkManager can access secrets
      Before = [ "graphical-session.target" ];
      # Make sure it's started early in the session
      PartOf = [ "graphical-session.target" ];
    };
  };

  programs.hyprlock = {
    enable = true;
  };

  services.hypridle = {
    enable = false;
    settings = {
      general = {
        lock_cmd = "hyprlock";
      };
    };
  };
}
