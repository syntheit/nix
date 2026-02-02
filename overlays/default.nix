{
  inputs,
  lib,
  ...
}:

let
  overlays = {
    modifications = final: prev: {
      antigravity =
        (import inputs.nixpkgs-unstable {
          system = final.system;
          config.allowUnfree = true;
        }).antigravity;
    };
    additions =
      final: _prev:
      import ../packages {
        inherit lib;
        pkgs = final;
      };
  };
in
overlays
