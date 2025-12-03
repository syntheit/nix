{
  pkgs,
  vars,
  extraLibs,
  inputs,
  ...
}:
{
  imports = extraLibs.scanPaths ./.;

  # Enable Wayland (no X11 needed for Hyprland)
  services.xserver.enable = false;

  # Enable display manager for Wayland
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  # Enable Hyprland (REQUIRED: NixOS module)
  # This enables critical components needed to run Hyprland properly, such as:
  # polkit, xdg-desktop-portal-hyprland, graphics drivers, fonts, dconf, xwayland,
  # and adds a proper Desktop Entry to the Display Manager.
  programs.hyprland = {
    enable = true;
    # Set the flake package (using development version from flake)
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # Make sure to also set the portal package, so that they are in sync
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

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
    
    # Monospace coding fonts
    fira-code
    fira-code-symbols
    hack-font
    iosevka
    source-code-pro
    victor-mono
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

