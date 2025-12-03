{
  inputs,
  lib,
  ...
}:

let
  overlays = {
    modifications = final: prev: {
    };
    additions = final: _prev: import ../packages {
      inherit lib;
      pkgs = final;
    };
  };
in
overlays

