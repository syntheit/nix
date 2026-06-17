{
  lib,
  stdenvNoCC,
  fetchFromGitLab,
}:

# ALSA UCM (Use-Case Manager) overlay for OnePlus 6T (fajita) / 6 (enchilada).
# Without this, the modem dials fine but voice calls have no audio because the
# mainline kernel's q6dsp graph card needs UCM mixer routing tables to wire
# AFE → backend DAIs. Vendored from the sdm845-mainline fork because upstream
# alsa-ucm-conf does not ship OnePlus device profiles.
#
# Files land at $out/share/alsa/ucm2/OnePlus/{enchilada,fajita}/ and are
# overlayed onto /etc/alsa/ucm2/ at the host level (see hosts/fajita).
# ALSA-lib checks /etc/alsa/ucm2/ before the stock /usr/share/alsa/ucm2/.
stdenvNoCC.mkDerivation {
  pname = "alsa-ucm-fajita";
  version = "0-unstable-2026-05-10";

  src = fetchFromGitLab {
    owner = "sdm845-mainline";
    repo = "alsa-ucm-conf";
    rev = "1b8d290e5aa2ca16b7f2fa8d74910ad19ef88b3a";
    hash = "sha256-Kg4vxDrli/ffNeUwDBL5GfdJsbwFRPAUieQEsjVKADw=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/alsa/ucm2/OnePlus
    cp -r ucm2/OnePlus/fajita    $out/share/alsa/ucm2/OnePlus/
    cp -r ucm2/OnePlus/enchilada $out/share/alsa/ucm2/OnePlus/
    runHook postInstall
  '';

  meta = {
    description = "ALSA UCM overlay for OnePlus 6/6T (sdm845-mainline fork)";
    homepage = "https://gitlab.com/sdm845-mainline/alsa-ucm-conf";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
