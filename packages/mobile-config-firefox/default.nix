{
  lib,
  stdenvNoCC,
  fetchFromGitLab,
}:

# pmOS's mobile-config-firefox — the userChrome.css + userContent.css bundles
# that rearrange Firefox's chrome to fit a phone screen. Upstream concatenates
# the per-feature CSS fragments at FF startup via mobile-config-autoconfig.js;
# we pre-concatenate at build time and let home-manager drop them into the
# user profile's chrome/ directory. Simpler, fully declarative.
#
# Pair with `programs.firefox.preferences."toolkit.legacyUserProfileCustomizations.stylesheets" = true`
# in the NixOS config (we already set it via the policies.json route).
stdenvNoCC.mkDerivation {
  pname = "mobile-config-firefox";
  version = "4.3.2";

  src = fetchFromGitLab {
    owner = "postmarketOS";
    repo = "mobile-config-firefox";
    rev = "4.3.2";
    hash = "sha256-AqRnf9wTr6sPLKgpHKFa/vgXBmiC7QulRpHP2ExdEPo=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    {
      cat src/common/header.css
      for f in src/userChrome/*.css; do
        printf '\n/* %s */\n' "$(basename $f)"
        cat "$f"
      done
    } > $out/userChrome.css
    {
      cat src/common/header.css
      for f in src/userContent/*.css; do
        printf '\n/* %s */\n' "$(basename $f)"
        cat "$f"
      done
    } > $out/userContent.css
    cp src/policies.json $out/upstream-policies.json
    runHook postInstall
  '';

  meta = {
    description = "Firefox userChrome + userContent for mobile from postmarketOS";
    homepage = "https://gitlab.com/postmarketOS/mobile-config-firefox";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
