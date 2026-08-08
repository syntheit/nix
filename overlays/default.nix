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
        jotter = inputs.jotter.packages.${final.stdenv.hostPlatform.system}.default;
        warden = inputs.warden.packages.${final.stdenv.hostPlatform.system}.default;
        courier = inputs.courier.packages.${final.stdenv.hostPlatform.system}.default;
        paloma = inputs.paloma.packages.${final.stdenv.hostPlatform.system}.default;
        # Runtime launcher: injects the Telegram api_id/api_hash from sops-decrypted
        # files (/run/secrets/paloma_api_{id,hash}) into the env before exec'ing the
        # real paloma binary — keeps the creds out of the nix store and the build
        # pure. If the secret files are absent (host without the secret), it falls
        # back to whatever PALOMA_API_* is already set (or none), so the app still
        # launches to its credentials page instead of crashing. The bundled .desktop
        # (Exec=paloma) and icon are inherited from the underlying package via
        # symlinkJoin, and its bin/paloma is overwritten by the wrapper here.
        paloma-wrapped = final.symlinkJoin {
          name = "paloma-wrapped";
          paths = [ final.paloma ];
          nativeBuildInputs = [ final.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/paloma \
              --run 'if [ -r /run/secrets/paloma_api_id ]; then export PALOMA_API_ID="$(cat /run/secrets/paloma_api_id)"; fi' \
              --run 'if [ -r /run/secrets/paloma_api_hash ]; then export PALOMA_API_HASH="$(cat /run/secrets/paloma_api_hash)"; fi'
          '';
          # Preserve meta (mainProgram = "paloma") so the desktop entry resolves.
          inherit (final.paloma) meta;
        };
        mimick = (import ../packages { inherit lib; pkgs = pkgsDefault; }).mimick;
      };
  };
in
overlays
