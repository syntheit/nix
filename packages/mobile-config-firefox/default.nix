{
  lib,
  stdenvNoCC,
  fetchFromGitLab,
}:

# pmOS's mobile-config-firefox — the userChrome.css + userContent.css bundles
# that rearrange Firefox's chrome to fit a phone screen. In 5.x the project
# switched to a chrome-registry/autoconfig module system, but the individual
# CSS files in src/themes/shared/{chrome,content}/ are still self-contained
# and can be concatenated into a static userChrome.css / userContent.css for
# profile-drop-in use.
#
# Key about:config pref (5.x): mcf.addressbarontop (default false = bottom bar)
# Set it to false (or leave unset) in programs.firefox.preferences to keep the
# nav bar at the bottom.
#
# Pair with `programs.firefox.preferences."toolkit.legacyUserProfileCustomizations.stylesheets" = true`
# in the NixOS config (we already set it via the policies.json route).
stdenvNoCC.mkDerivation {
  pname = "mobile-config-firefox";
  version = "5.1.0";

  src = fetchFromGitLab {
    domain = "gitlab.postmarketos.org";
    owner = "postmarketOS";
    repo = "mobile-config-firefox";
    rev = "5.1.0";
    hash = "sha256-+iZjSZbds/t4CZnquxzNUBzCtr3UDD1JNE8KGr+hmCc=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    {
      for f in src/themes/shared/chrome/*.css; do
        printf '\n/* %s */\n' "$(basename $f)"
        cat "$f"
      done
    } > $out/userChrome.css
    {
      for f in src/themes/shared/content/*.css; do
        printf '\n/* %s */\n' "$(basename $f)"
        cat "$f"
      done
    } > $out/userContent.css
    cp src/policies.json $out/upstream-policies.json
    runHook postInstall
  '';

  meta = {
    description = "Firefox userChrome + userContent for mobile from postmarketOS";
    homepage = "https://gitlab.postmarketos.org/postmarketOS/mobile-config-firefox";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
