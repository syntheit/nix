{
  inputs,
  pkgs,
  config,
  hostName,
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
    # `u` in the System popup (fn+X / Super+X) rebuilds this host in the
    # background: Touch ID on macOS, the polkit dialog on Linux.
    system.rebuild =
      let
        flake = "${config.home.homeDirectory}/nix#${hostName}";
      in
      if pkgs.stdenv.hostPlatform.isDarwin then
        [
          "/run/current-system/sw/bin/darwin-rebuild"
          "switch"
          "--flake"
          flake
          # Determinate's cache is flaky; cache.nixos.org only.
          "--substituters"
          "https://cache.nixos.org"
        ]
      else
        [
          "/run/current-system/sw/bin/nixos-rebuild"
          "switch"
          "--flake"
          flake
        ];
    # Clipboard history (fn+C / Super+V): last 50 items, 30 days, pins kept.
    clipboard.enable = true;
    hyprland.binds = {
      net = "SUPER, N";
      bt = "SUPER, B";
      sound = "SUPER, M";
      display = "SUPER, D";
      perf = "SUPER, I";
      power = "SUPER, U";
      system = "SUPER, X";
      clipboard = "SUPER, C"; # matches fn+C on swift
    };
  };
}
