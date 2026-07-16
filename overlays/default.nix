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
      let
        # Mimick needs gtk4 >= 4.22 (gdk4-sys asserts it), but fajita's pinned
        # nixpkgs-gnome49 is on 4.20.3. Build Mimick (and its whole closure) from
        # the default nixpkgs, which is on 4.22 — it's a standalone app, so it can
        # carry its own gtk4 without touching the mobile-shell gtk4 pin. Lazy:
        # pkgsDefault is only instantiated on a host that actually pulls mimick
        # (just fajita), so other hosts pay nothing.
        pkgsDefault = import inputs.nixpkgs {
          inherit (final.stdenv.hostPlatform) system;
          config.allowUnfree = true;
        };
      in
      (import ../packages {
        inherit lib;
        pkgs = final;
      })
      // {
        foyer = inputs.foyer.packages.${final.stdenv.hostPlatform.system}.default;
        elliot = inputs.elliot.packages.${final.stdenv.hostPlatform.system}.default;
        jelly-recs = inputs.jelly-recs.packages.${final.stdenv.hostPlatform.system}.default;
        anchorage = inputs.anchorage.packages.${final.stdenv.hostPlatform.system}.default;
        mimick = (import ../packages { inherit lib; pkgs = pkgsDefault; }).mimick;
      };
  };
in
overlays
