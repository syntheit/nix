{ pkgs, ... }:

{
  home.sessionVariables = {
    DEFAULT_USER = "`whoami`";
    NIXOS_OZONE_WL = "1";
    EDITOR = "nvim";
    BROWSER = "zen";
    LIBVA_DRIVER_NAME = "nvidia";
    XDG_SESSION_TYPE = "wayland";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    # Force dark theme for libadwaita apps
    GTK_THEME = "Adwaita-dark";
  };

  # GTK configuration
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk3.extraCss = ''
      @define-color theme_selected_bg_color #1e3a5f;
      @define-color theme_selected_fg_color #ffffff;
    '';
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraCss = ''
      @define-color accent_bg_color #1e3a5f;
      @define-color accent_fg_color #ffffff;
      @define-color accent_color #1e3a5f;
    '';
  };

  home.pointerCursor = {
    gtk.enable = true;
    package = pkgs.kdePackages.breeze;
    name = "breeze_cursors";
    size = 24;
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "dark";
      gtk-theme = "Adwaita-dark";
      gtk-application-prefer-dark-theme = true;
    };
    # Additional settings for libadwaita apps
    "org/gnome/desktop/wm/preferences" = {
      theme = "Adwaita-dark";
    };
  };

  qt = {
    enable = true;
    style.name = "adwaita-dark";
    platformTheme.name = "adwaita";
  };
}
