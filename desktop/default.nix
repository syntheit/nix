{
  pkgs,
  extraLibs,
  ...
}:
{
  imports = extraLibs.scanPaths ./.;

  # Enable Wayland (no X11 needed for Hyprland)
  services.xserver.enable = false;

  # Enable greetd with tuigreet for minimalist login experience
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # Use tuigreet.
        # --time: Display the date/time.
        # --asterisks: Mask the password.
        # --remember: Remember the last logged-in username.
        # --cmd start-hyprland: launches Hyprland via the wrapper the NixOS
        # hyprland module ships (programs.hyprland.enable). Launching the raw
        # `Hyprland` binary directly triggers Hyprland's own startup warning
        # ("WARNING: Hyprland is being launched without start-hyprland."),
        # confirmed in ~/.cache/hyprland/*.log — start-hyprland does the
        # session env/systemd setup Hyprland now expects.
        command = "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --remember --cmd start-hyprland";
        user = "greeter";
      };
    };
  };

  # Enable Hyprland (REQUIRED: NixOS module)
  # This enables critical components needed to run Hyprland properly, such as:
  # polkit, xdg-desktop-portal-hyprland, graphics drivers, fonts, dconf, xwayland,
  # and adds a proper Desktop Entry to the Display Manager.
  programs.hyprland.enable = true;

  programs.steam.enable = true;

  # Firefox disabled - using zen-browser instead
  # programs.firefox.enable = true;

  fonts.packages = with pkgs; [
    # Nerd Fonts (popular coding fonts with icons)
    nerd-fonts._0xproto
    nerd-fonts.caskaydia-cove
    nerd-fonts.droid-sans-mono
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    nerd-fonts.hack
    nerd-fonts.iosevka
    nerd-fonts.jetbrains-mono
    nerd-fonts.meslo-lg
    nerd-fonts.monofur
    nerd-fonts.mononoki
    nerd-fonts.roboto-mono
    nerd-fonts.sauce-code-pro
    nerd-fonts.ubuntu-mono
    nerd-fonts.victor-mono
    nerd-fonts.ubuntu

    # System and UI fonts
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
    noto-fonts-lgc-plus

    # Popular sans-serif fonts
    inter
    roboto
    open-sans
    source-sans-pro
    source-sans

    # Popular serif fonts
    source-serif-pro
    libertinus
    eb-garamond

    # Monospace coding fonts (base variants covered by Nerd Fonts above)
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    inconsolata
    terminus_font

    # Icon fonts
    font-awesome
    material-icons
    material-design-icons
  ];
}
