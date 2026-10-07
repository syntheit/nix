{
  inputs,
  ...
}:

# Telmo popups (github:syntheit/telmo): network, bluetooth and sound.
# macOS: Telmo.app runs at login; skhd binds fn+N/B/M to `telmo popup …`
# (hosts/*/skhdrc). Hyprland: the binds and window rules come from the module.
{
  imports = [ inputs.telmo.homeManagerModules.default ];

  programs.telmo = {
    enable = true;
    # macOS only: a stable signature keeps the Location (Wi-Fi names) and
    # Bluetooth permissions across rebuilds.
    signingIdentity = "Developer ID Application: Daniel Miller (6NHZWHQX37)";
    # btop, bigger than the built-in popups; Esc closes it.
    popups.perf = {
      command = [ "btop" ];
      size = "large";
      escape = "close";
    };
    hyprland.binds = {
      net = "SUPER, N";
      bt = "SUPER, B";
      sound = "SUPER, M";
      display = "SUPER, D";
      perf = "SUPER, I";
      power = "SUPER, U";
    };
  };
}
