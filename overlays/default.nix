{
  inputs,
  lib,
  ...
}:

let
  overlays = {
    modifications = final: prev: {
      antigravity = inputs.antigravity.packages.${final.stdenv.hostPlatform.system}.default;
      direnv = prev.direnv.overrideAttrs { doCheck = false; };
    };
    additions =
      final: _prev:
      (import ../packages {
        inherit lib;
        pkgs = final;
      })
      // {
        foyer = inputs.foyer.packages.${final.stdenv.hostPlatform.system}.default;
        elliot = inputs.elliot.packages.${final.stdenv.hostPlatform.system}.default;
      };
  };
in
overlays
