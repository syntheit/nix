{
  inputs,
  lib,
  ...
}:

let
  overlays = {
    modifications = final: prev: {
      antigravity = inputs.antigravity.packages.${final.stdenv.hostPlatform.system}.default;

      # TEMP: claude-code 2.1.88 was removed from npm. Pin to 2.1.87 until nixpkgs updates.
      claude-code = prev.claude-code.overrideAttrs (old: rec {
        version = "2.1.87";
        src = prev.fetchzip {
          url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
          hash = "sha256-jorpY6ao1YgkoTgIk1Ae2BQCbqOuEtwzoIG36BP5nG4=";
        };
        npmDeps = prev.fetchNpmDeps {
          inherit src;
          name = "claude-code-${version}-npm-deps";
          postPatch = old.postPatch;
          hash = "sha256-izy3dQProZIdUF5Z11fvGQOm/TBcWGhDK8GvNs8gG5E=";
        };
      });
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
