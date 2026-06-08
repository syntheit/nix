{
  pkgs,
  config,
  ...
}:
{
  imports = [
    ../../home/darwin.nix
    # MacBook-only: brightness-panel drives the internal display via pmset; the
    # mini's external monitors don't expose software brightness through that
    # path, so it stays out of hosts/mini/home.nix.
    ../../home/modules/brightness-panel.nix
  ];

  # Karabiner config managed declaratively. GUI edits in Karabiner-Elements
  # will fail to write (symlink → /nix/store, read-only) — change here
  # instead and rebuild. fn_function_keys: F3/F4 stay as standard keycodes
  # so skhd can catch them. complex_modifications: caps_lock → fn.
  home.file.".config/karabiner/karabiner.json".source =
    (pkgs.formats.json { }).generate "karabiner.json" {
      profiles = [{
        name = "Default profile";
        selected = true;
        virtual_hid_keyboard.keyboard_type_v2 = "ansi";
        fn_function_keys = [
          { from.key_code = "f1"; to = [{ consumer_key_code = "display_brightness_decrement"; }]; }
          { from.key_code = "f2"; to = [{ consumer_key_code = "display_brightness_increment"; }]; }
          { from.key_code = "f3"; to = [{ key_code = "f3"; }]; }
          { from.key_code = "f4"; to = [{ key_code = "f4"; }]; }
          { from.key_code = "f5"; to = [{ key_code = "f5"; }]; }
          { from.key_code = "f6"; to = [{ key_code = "f6"; }]; }
          { from.key_code = "f7"; to = [{ consumer_key_code = "rewind"; }]; }
          { from.key_code = "f8"; to = [{ consumer_key_code = "play_or_pause"; }]; }
          { from.key_code = "f9"; to = [{ consumer_key_code = "fast_forward"; }]; }
          { from.key_code = "f10"; to = [{ consumer_key_code = "mute"; }]; }
          { from.key_code = "f11"; to = [{ consumer_key_code = "volume_decrement"; }]; }
          { from.key_code = "f12"; to = [{ consumer_key_code = "volume_increment"; }]; }
        ];
        complex_modifications.rules = [
          {
            description = "Change caps_lock to fn";
            manipulators = [{
              type = "basic";
              from = {
                key_code = "caps_lock";
                modifiers.optional = [ "any" ];
              };
              to = [{ key_code = "fn"; }];
            }];
          }
          {
            description = "Shift + brightness keys → keyboard backlight";
            manipulators = [
              {
                type = "basic";
                from = {
                  key_code = "f1";
                  modifiers = {
                    mandatory = [ "shift" ];
                    optional = [ "any" ];
                  };
                };
                to = [{ shell_command = "${config.home.homeDirectory}/.local/bin/brightness-key down keyboard"; }];
              }
              {
                type = "basic";
                from = {
                  key_code = "f2";
                  modifiers = {
                    mandatory = [ "shift" ];
                    optional = [ "any" ];
                  };
                };
                to = [{ shell_command = "${config.home.homeDirectory}/.local/bin/brightness-key up keyboard"; }];
              }
            ];
          }
        ];
      }];
    };
}
