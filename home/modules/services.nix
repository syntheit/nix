{ ... }:

{
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
    extraConfig = ''
      background {
        monitor =
        path = ~/.config/hypr/wallpaper.png
        blur_passes = 2
      }

      input-field {
        monitor =
        size = 250, 60
        outline_thickness = 2
        dots_size = 0.2
        dots_spacing = 0.2
        dots_center = true
        outer_color = rgba(0, 0, 0, 0)
        inner_color = rgba(0, 0, 0, 0.5)
        font_color = rgb(200, 200, 200)
        fade_on_empty = false
        placeholder_text = <i><span foreground="##cdd6f4">Input Password...</span></i>
        hide_input = false
        position = 0, -120
        halign = center
        valign = center
      }

      label {
        monitor =
        text = cmd[update:1000] echo "$(date +"%-I:%M%p")"
        color = rgba(255, 255, 255, 0.6)
        font_size = 120
        font_family = JetBrains Mono Nerd Font Mono ExtraBold
        position = 0, -300
        halign = center
        valign = top
      }

      label {
        monitor =
        text = Hi there, $USER
        color = rgba(255, 255, 255, 0.6)
        font_size = 25
        font_family = JetBrains Mono Nerd Font Mono
        position = 0, -40
        halign = center
        valign = center
      }
    '';
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
