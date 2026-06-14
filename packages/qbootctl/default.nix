{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  linuxHeaders,
}:

stdenv.mkDerivation rec {
  pname = "qbootctl";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "linux-msm";
    repo = "qbootctl";
    rev = version;
    sha256 = "01hm5f50z31mqdyg4rvqp4bnqiq8rrbi07bym6zr5qj9si9w544n";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    linuxHeaders
  ];

  meta = {
    description = "Qualcomm A/B slot boot control — marks current slot good after successful boot";
    homepage = "https://github.com/linux-msm/qbootctl";
    license = lib.licenses.gpl3Only;
    mainProgram = "qbootctl";
    platforms = lib.platforms.linux;
  };
}
