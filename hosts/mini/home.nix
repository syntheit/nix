{ pkgs, ... }:
{
  imports = [
    ../../home/darwin.nix
  ];

  # Intentionally minimal. brightness-panel is MacBook-only (drives the
  # internal panel via pmset); the mini's external monitors don't expose
  # software brightness through that path, so we skip it.

  # Karabiner on the mini does TWO things, both narrow:
  #
  # 1. Remap the Keychron Q1 Pro's Mac-mode F-row from Apple consumer codes
  #    (display_brightness_decrement, mission_control, …) back to raw F1–F6
  #    so skhd's `f1`..`f6` bindings catch them as workspace switchers.
  #    F7–F12 are NOT remapped so volume/media keys still fire natively.
  #
  # 2. Remap caps_lock → fn so skhd's `fn -` bindings (window mgmt, app
  #    launchers) work. Apple's fn key isn't emitted as a normal modifier
  #    on any external keyboard, including the Q1 Pro.
  #
  # We do NOT use Karabiner's fn_function_keys rule — that's for built-in
  # Mac keyboards' F-row, which the Q1 Pro isn't. Edits in Karabiner's GUI
  # will silently fail (the file is a symlink into /nix/store, read-only);
  # change here and rebuild instead.
  home.file.".config/karabiner/karabiner.json".source =
    (pkgs.formats.json { }).generate "karabiner.json" {
      profiles = [{
        name = "Default profile";
        selected = true;
        virtual_hid_keyboard.keyboard_type_v2 = "ansi";
        complex_modifications.rules = [
          {
            description = "Keychron Q1 Pro Mac-mode F-row → raw F1–F6";
            manipulators = [
              { type = "basic"; from.consumer_key_code = "display_brightness_decrement"; to = [{ key_code = "f1"; }]; }
              { type = "basic"; from.consumer_key_code = "display_brightness_increment"; to = [{ key_code = "f2"; }]; }
              { type = "basic"; from.apple_vendor_keyboard_key_code = "mission_control"; to = [{ key_code = "f3"; }]; }
              { type = "basic"; from.apple_vendor_keyboard_key_code = "launchpad"; to = [{ key_code = "f4"; }]; }
              { type = "basic"; from.apple_vendor_keyboard_key_code = "spotlight"; to = [{ key_code = "f4"; }]; }
              { type = "basic"; from.apple_vendor_keyboard_key_code = "dictation"; to = [{ key_code = "f5"; }]; }
              { type = "basic"; from.apple_vendor_keyboard_key_code = "do_not_disturb"; to = [{ key_code = "f6"; }]; }
            ];
          }
          {
            description = "caps_lock → fn (so skhd can see the fn modifier)";
            manipulators = [{
              type = "basic";
              from = {
                key_code = "caps_lock";
                modifiers.optional = [ "any" ];
              };
              to = [{ key_code = "fn"; }];
            }];
          }
        ];
      }];
    };
}
