{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

# MrOtherGuy/fx-autoconfig — privileged-chrome JS loader for Firefox.
#
# This package just exposes the upstream source tree so other parts of the
# config can reference individual files without re-fetching.  The two install
# tiers are wired up elsewhere:
#
#   Program tier (affects ALL profiles on the binary):
#     programs.firefox.autoConfig = builtins.readFile "${pkgs.fx-autoconfig}/program/config.js";
#     → NixOS firefox module concatenates this into mozilla.cfg (after its own
#       leading comment line, so the "// skip 1st line" in config.js is safe —
#       Firefox skips mozilla.cfg line 1, which is the wrapper's own comment).
#
#   Profile tier (per-profile, in chrome/utils/):
#     home.file entries pointing at ${pkgs.fx-autoconfig}/profile/chrome/utils/*
#     → chrome.manifest + boot.sys.mjs + fs.sys.mjs + utils.sys.mjs +
#       uc_api.sys.mjs + module_loader.mjs
#
# Pinned to master @ 2026-07-19.
# Rev: d469a80f12e286c0e937d8b93c01dfc2d55dca8f
stdenvNoCC.mkDerivation {
  pname = "fx-autoconfig";
  version = "0-unstable-2026-07-19";

  src = fetchFromGitHub {
    owner = "MrOtherGuy";
    repo = "fx-autoconfig";
    rev = "d469a80f12e286c0e937d8b93c01dfc2d55dca8f";
    hash = "sha256-czNgt62fofg3hXw7F4wXSv/+ZAsGtO6bg3sUOiUXcu4=";
  };

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';

  meta = {
    description = "Userscript loader for Firefox via autoconfig (fx-autoconfig)";
    homepage = "https://github.com/MrOtherGuy/fx-autoconfig";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
