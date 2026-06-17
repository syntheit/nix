{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  json_c,
}:

stdenv.mkDerivation {
  pname = "hexagonrpc";
  # Past v0.4.0 — the v0.4.0 tarball is missing data/ (systemd units were
  # added after the tag). Pinning to a known-good main HEAD.
  version = "0.4.0-unstable-2026-06-14";

  src = fetchFromGitHub {
    owner = "linux-msm";
    repo = "hexagonrpc";
    rev = "dd9ac70c026e1bad93e8cffa3801255b8ceb551e";
    sha256 = "09hhasnfz53rwh10y2yqr402dzqsjiddzwz889xdlsm9daaiws8i";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    json_c
  ];

  # Upstream's meson installs `configure_file(install: true)` for the .service.in
  # templates, but newer meson deprecated that — the units silently get dropped.
  # Install them ourselves with the bindir substitution upstream wanted.
  postInstall = ''
    mkdir -p $out/lib/systemd/system
    for unit in hexagonrpcd-adsp-rootpd hexagonrpcd-adsp-sensorspd hexagonrpcd-sdsp; do
      substitute "$NIX_BUILD_TOP/source/data/$unit.service.in" \
        "$out/lib/systemd/system/$unit.service" \
        --replace-fail '@bindir@' "$out/bin"
    done
  '';

  meta = {
    description = "FastRPC wrapper and reverse tunnel for Qualcomm Hexagon DSPs (sensor bridge for SDM845/etc.)";
    homepage = "https://github.com/linux-msm/hexagonrpc";
    license = lib.licenses.gpl3Only;
    mainProgram = "hexagonrpcd";
    platforms = lib.platforms.linux;
  };
}
