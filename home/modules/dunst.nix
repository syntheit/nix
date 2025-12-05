{ pkgs, lib, ... }:

{
  services.dunst = {
    enable = true;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    settings = {
      global = {
        follow = "keyboard";  # Follow monitor with keyboard focus (works better in Wayland)
        width = 300;  # Fixed width, height will auto-size
        offset = "30x30";
        origin = "top-right";
        transparency = 10;
        frame_color = "#7aa2f7"; # Single manual color (Border) just in case, but Stylix usually overrides
        font = lib.mkForce "JetBrainsMono Nerd Font 10";
        format = "<b>%s</b>\n%b";  # Hide app name, show only summary and body
      };
      
      urgency_normal = {
        timeout = 10;
      };
    };
  };
}
