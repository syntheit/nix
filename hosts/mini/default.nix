{
  pkgs,
  lib,
  ...
}:

let
  tccGrants = import ./tcc-grants.nix { inherit pkgs; };
in
{
  imports = [
    ../../modules/darwin/common.nix
    ./homebrew.nix
  ];

  networking.hostName = "mini";

  matv.darwin.tccGrants = tccGrants;

  # Mac mini has no TouchID — no PAM hooks needed. Sudo works via password
  # as usual. (Magic Keyboard with TouchID would re-enable this; if you ever
  # add one, copy the two lines from hosts/swift/default.nix.)

  # fnState is not set here. The Keychron Q1 Pro in Mac mode sends Apple
  # consumer codes (brightness_down, mission_control, …) on the F-row
  # regardless of fnState — that pref only inverts Apple-keyboard behavior.
  # Karabiner-Elements (hosts/mini/home.nix) does the consumer-to-raw-F-key
  # remap so skhd's f1-f6 bindings fire, and remaps caps_lock → fn so the
  # fn-modifier bindings in skhdrc work too.

  services.skhd = {
    enable = true;
    package = pkgs.skhd;
    skhdConfig = builtins.readFile ./skhdrc;
  };
}
