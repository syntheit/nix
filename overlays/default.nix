{
  inputs,
  lib,
  ...
}:

let
  overlays = {
    modifications = final: prev: {
      antigravity = inputs.antigravity.packages.${final.stdenv.hostPlatform.system}.default;
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
