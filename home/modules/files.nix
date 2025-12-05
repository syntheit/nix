{ ... }:

{
  # Wallpaper is managed by Stylix (via stylix.image and stylix.targets.hyprland.enable)
  # hyprpaper config removed - Stylix handles wallpaper configuration

  # Create hyprlock config file
  home.file.".config/hypr/hyprlock.conf".text = ''
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

  # monitors.conf is managed by nwg-displays, not Home Manager
  # This allows nwg-displays to save monitor configurations without being overwritten
}
